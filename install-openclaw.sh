#!/bin/bash
set -e

# --- Cấu hình ---
INSTALL_DIR="$HOME/openclaw"
IMAGE="ghcr.io/openclaw/openclaw:latest"
PORT=80
MODEL="openrouter/minimax/minimax-m2.5:free"

# --- Màu sắc ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== OpenClaw Docker Installer for Ubuntu ===${NC}"

# 1. Kiểm tra và cài đặt Docker/Docker Compose
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Đang cài đặt Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo -e "${GREEN}Docker đã được cài đặt.${NC}"
fi

if ! docker compose version &> /dev/null; then
    echo -e "${YELLOW}Đang cài đặt Docker Compose...${NC}"
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
fi

# 2. Tạo thư mục cài đặt
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
mkdir -p config workspace

# 3. Nhập API Key OpenRouter
echo -e "${BLUE}Vui lòng nhập OpenRouter API Key của bạn:${NC}"
read -r OPENROUTER_API_KEY

if [ -z "$OPENROUTER_API_KEY" ]; then
    echo -e "${YELLOW}Cảnh báo: Không có API Key. Bạn sẽ cần cấu hình nó sau trong file .env${NC}"
fi

# 4. Tạo Gateway Token ngẫu nhiên
GATEWAY_TOKEN=$(openssl rand -hex 32)

# 5. Tạo file .env
cat <<EOF > .env
OPENCLAW_IMAGE=$IMAGE
OPENCLAW_GATEWAY_PORT=$PORT
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
OPENCLAW_CONFIG_DIR=$(pwd)/config
OPENCLAW_WORKSPACE_DIR=$(pwd)/workspace
OPENROUTER_API_KEY=$OPENROUTER_API_KEY
OPENCLAW_GATEWAY_BIND=lan
EOF

# 6. Tạo file docker-compose.yml (Tối ưu cho yêu cầu của bạn)
cat <<EOF > docker-compose.yml
services:
  openclaw-gateway:
    image: \${OPENCLAW_IMAGE}
    container_name: openclaw-gateway
    restart: unless-stopped
    ports:
      - "\${OPENCLAW_GATEWAY_PORT}:18789"
    environment:
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
      - OPENROUTER_API_KEY=\${OPENROUTER_API_KEY}
      - TZ=Asia/Ho_Chi_Minh
    volumes:
      - \${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - \${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "lan",
        "--port",
        "18789",
      ]

  openclaw-cli:
    image: \${OPENCLAW_IMAGE}
    network_mode: "service:openclaw-gateway"
    environment:
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
    volumes:
      - \${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - \${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    stdin_open: true
    tty: true
    entrypoint: ["node", "dist/index.js"]
EOF

# 7. Tải Image
echo -e "${YELLOW}Đang tải OpenClaw Docker image...${NC}"
docker compose pull openclaw-gateway

# 8. Cấu hình model
echo -e "${YELLOW}Đang thiết lập Model: $MODEL...${NC}"

# Sửa lỗi phân quyền (Permission fix)
echo -e "${YELLOW}Đang sửa lỗi phân quyền cho thư mục data...${NC}"
docker compose run --rm --user root --entrypoint sh openclaw-gateway -c \
  "chown -R 1000:1000 /home/node/.openclaw && chown -R 1000:1000 /home/node/.openclaw/workspace"

# Chạy onboarding cơ bản (không cài daemon vì dùng docker)
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js onboard --mode local --no-install-daemon

# Thiết lập model mặc định
docker compose run --rm --no-deps --entrypoint node openclaw-gateway \
  dist/index.js models set "$MODEL"

# 9. Khởi chạy
echo -e "${YELLOW}Đang khởi động OpenClaw...${NC}"
docker compose up -d openclaw-gateway

echo -e "${GREEN}=== Cài đặt hoàn tất! ===${NC}"
echo -e "Địa chỉ truy cập: ${BLUE}http://localhost${NC} (hoặc IP của server)"
echo -e "Gateway Token: ${YELLOW}$GATEWAY_TOKEN${NC}"
echo -e "Thư mục cấu hình: $INSTALL_DIR"
