#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
HOSTNAME=""
EMAIL=""
TIMEZONE="UTC"
WORKFLOWS_REPO=""

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    echo "Usage: $0 --hostname <hostname> --email <email> [--timezone <timezone>] [--workflows-repo <repo_url>]"
    echo ""
    echo "Required arguments:"
    echo "  --hostname        Hostname for n8n (e.g., n8n.eastus.cloudapp.azure.com)"
    echo "  --email           Email address for Let's Encrypt certificate"
    echo ""
    echo "Optional arguments:"
    echo "  --timezone        Timezone (default: UTC)"
    echo "  --workflows-repo  GitHub repository URL for workflows (optional)"
    echo ""
    echo "Example:"
    echo "  $0 --hostname n8n.eastus.cloudapp.azure.com --email admin@example.com --timezone Asia/Ho_Chi_Minh"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --email)
            EMAIL="$2"
            shift 2
            ;;
        --timezone)
            TIMEZONE="$2"
            shift 2
            ;;
        --workflows-repo)
            WORKFLOWS_REPO="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$HOSTNAME" ]; then
    print_error "Hostname is required"
    usage
fi

if [ -z "$EMAIL" ]; then
    print_error "Email is required"
    usage
fi

print_info "Starting n8n deployment with Docker, Nginx, and Let's Encrypt"
print_info "Hostname: $HOSTNAME"
print_info "Email: $EMAIL"
print_info "Timezone: $TIMEZONE"
if [ -n "$WORKFLOWS_REPO" ]; then
    print_info "Workflows Repository: $WORKFLOWS_REPO"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Update system packages
print_info "Updating system packages..."
apt-get update && apt-get upgrade -y

# Install Docker if not installed
if ! command -v docker &> /dev/null; then
    print_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    print_info "Docker is already installed"
fi

# Install Docker Compose if not installed
if ! command -v docker-compose &> /dev/null; then
    print_info "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    print_info "Docker Compose is already installed"
fi

# Create necessary directories
print_info "Creating directory structure..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/n8n"
mkdir -p "$DEPLOY_DIR"/{nginx/conf.d,certbot/www,certbot/conf,workflows}

# Copy configuration files
print_info "Copying configuration files..."
cp "$SCRIPT_DIR/docker-compose.yml" "$DEPLOY_DIR/"
cp "$SCRIPT_DIR/nginx/nginx.conf" "$DEPLOY_DIR/nginx/"
# Clear any existing configs to prevent startup crashes and account sync issues
rm -rf "$DEPLOY_DIR/nginx/conf.d"/*
rm -rf "$DEPLOY_DIR/certbot/conf"/*

# Generate nginx config from template (save as .full until SSL is ready)
print_info "Generating Nginx configuration..."
sed "s/\${HOSTNAME}/$HOSTNAME/g" "$SCRIPT_DIR/nginx/conf.d/n8n.conf.template" > "$DEPLOY_DIR/nginx/conf.d/n8n.conf.full"

# Create .env file
print_info "Creating environment file..."
cat > "$DEPLOY_DIR/.env" << EOF
HOSTNAME=$HOSTNAME
EMAIL=$EMAIL
TIMEZONE=$TIMEZONE
EOF

# Clone workflows repository if provided
if [ -n "$WORKFLOWS_REPO" ]; then
    print_info "Cloning workflows repository..."
    cd "$DEPLOY_DIR/workflows"
    git init
    if [[ "$WORKFLOWS_REPO" == *"@github.com"* ]] || [[ "$WORKFLOWS_REPO" == *"https://github.com"* ]]; then
        # For public repos or if SSH keys are configured
        git remote add origin "$WORKFLOWS_REPO" || true
        git fetch origin
        git checkout -b main
        git pull origin main || git pull origin master || true
    fi
    cd "$DEPLOY_DIR"
fi

# Set proper permissions
print_info "Setting permissions..."
chown -R 1000:1000 "$DEPLOY_DIR/workflows"
chmod -R 755 "$DEPLOY_DIR"

# Start containers for initial setup (without SSL first)
print_info "Starting initial containers..."
cd "$DEPLOY_DIR"

# Create a temporary nginx config for HTTP only (for certificate generation)
cat > "$DEPLOY_DIR/nginx/conf.d/n8n-temp.conf" << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
EOF

# Ensure nginx is stopped first to pick up new config and break restart loops
docker-compose stop nginx || true
docker-compose up -d nginx certbot

# Wait for nginx to be ready
sleep 5

# Generate SSL certificate
print_info "Requesting SSL certificate from Let's Encrypt..."
docker-compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d "$HOSTNAME"

if [ $? -eq 0 ]; then
    print_info "SSL certificate obtained successfully!"
    
    # Remove temporary config and use full config
    rm -f "$DEPLOY_DIR/nginx/conf.d/n8n-temp.conf"
    mv "$DEPLOY_DIR/nginx/conf.d/n8n.conf.full" "$DEPLOY_DIR/nginx/conf.d/n8n.conf"
    
    # Restart nginx with full SSL configuration
    print_info "Restarting services with HTTPS..."
    docker-compose down nginx
    docker-compose up -d
    
    print_info "Deployment completed successfully!"
    print_info "Access n8n at: https://$HOSTNAME"
    print_info ""
    print_warning "IMPORTANT: Make sure DNS record for $HOSTNAME points to this server's IP"
    print_warning "Azure DNS example: az network dns record-set a create --resource-group <RG> --zone-name <ZONE> --name n8n --ttl 3600"
    print_warning "Then add record: az network dns record-set a add-record --resource-group <RG> --zone-name <ZONE> --record-set-name n8n --ipv4-address <YOUR_VM_IP>"
else
    print_error "Failed to obtain SSL certificate"
    print_error "Make sure DNS is properly configured and port 80 is accessible"
    exit 1
fi

# Setup auto-renewal cron job
print_info "Setting up automatic certificate renewal..."
(crontab -l 2>/dev/null; echo "0 0 1 * * cd $DEPLOY_DIR && docker-compose run --rm certbot renew && docker-compose restart nginx") | crontab -

print_info ""
print_info "=========================================="
print_info "n8n Deployment Complete!"
print_info "=========================================="
print_info "URL: https://$HOSTNAME"
print_info "Data directory: $DEPLOY_DIR"
print_info "Workflows directory: $DEPLOY_DIR/workflows"
print_info ""
if [ -n "$WORKFLOWS_REPO" ]; then
    print_info "To sync workflows from GitHub:"
    print_info "  cd $DEPLOY_DIR/workflows && git pull"
fi
print_info "=========================================="
