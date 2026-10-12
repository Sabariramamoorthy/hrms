#!/bin/bash
set -e

# Frappe startup script for Openship deployment
# Initializes the Frappe bench and starts the app

export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

BENCH_DIR="/home/frappe/frappe-bench"
SITE_NAME="${SITE_NAME:-hrms.localhost}"

echo "Starting Frappe HRMS..."

# Check if bench already exists
if [ ! -d "$BENCH_DIR" ]; then
    echo "Initializing Frappe bench..."
    cd /home/frappe
    
    # Initialize bench with specified database host
    bench init --skip-redis-config-generation frappe-bench
    
    cd frappe-bench
    
    # Configure database and cache connections
    echo "Configuring database and cache..."
    bench set-mariadb-host "${FRAPPE_DB_HOST:-db}"
    bench set-redis-cache-host "redis://${REDIS_HOST:-redis}:${REDIS_PORT:-6379}"
    bench set-redis-queue-host "redis://${REDIS_HOST:-redis}:${REDIS_PORT:-6379}"
    bench set-redis-socketio-host "redis://${REDIS_HOST:-redis}:${REDIS_PORT:-6379}"
    
    # Remove redis and watch from Procfile (running as separate services)
    sed -i '/redis/d' ./Procfile
    sed -i '/watch/d' ./Procfile
    
    # Install required apps
    echo "Installing ERPNext and HRMS apps..."
    bench get-app erpnext
    bench get-app /workspace
    
    # Create site with HRMS
    echo "Creating site: $SITE_NAME..."
    bench new-site "$SITE_NAME" \
        --force \
        --mariadb-root-password "${MYSQL_ROOT_PASSWORD:-root123}" \
        --admin-password "admin@123" \
        --no-mariadb-socket
    
    # Install HRMS app on site
    echo "Installing HRMS app..."
    bench --site "$SITE_NAME" install-app hrms
    
    # Configure site
    bench --site "$SITE_NAME" set-config developer_mode 0
    bench --site "$SITE_NAME" enable-scheduler
    bench --site "$SITE_NAME" clear-cache
    
    # Set default site
    bench use "$SITE_NAME"
    
    echo "Bench initialization complete!"
else
    echo "Bench already exists, starting services..."
    cd "$BENCH_DIR"
fi

# Start Frappe services
echo "Starting Frappe services..."
bench --host "${HOST:-0.0.0.0}" --port "${PORT:-8000}" start
