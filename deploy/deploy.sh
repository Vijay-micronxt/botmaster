#!/bin/bash
# =============================================================================
# deploy.sh — WhatsApp Proxy setup on existing Frappe EC2 (ubuntu, Supervisor)
# Run as: bash deploy.sh
# =============================================================================

set -e  # Exit immediately on any error

APP_DIR="/home/ubuntu/whatsapp-proxy"
DOMAIN="botmaster.storenxt.in"
NGINX_CONF="/etc/nginx/conf.d/whatsapp-proxy.conf"
SUPERVISOR_CONF="/etc/supervisor/conf.d/whatsapp-proxy.conf"

echo ""
echo "══════════════════════════════════════════"
echo "  WhatsApp Proxy — Deployment Starting"
echo "══════════════════════════════════════════"
echo ""

# ── Step 1: Create app directory ─────────────────────────────────────────────
echo "▶ [1/6] Setting up app directory at $APP_DIR"
mkdir -p "$APP_DIR"
cp main.py "$APP_DIR/main.py"
cp requirements.txt "$APP_DIR/requirements.txt"
echo "    ✓ Files copied"

# ── Step 2: Python virtual environment ───────────────────────────────────────
echo "▶ [2/6] Creating Python virtual environment"
cd "$APP_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip -q
pip install -r requirements.txt -q
deactivate
echo "    ✓ Virtualenv ready at $APP_DIR/venv"

# ── Step 3: Supervisor config ─────────────────────────────────────────────────
echo "▶ [3/6] Installing Supervisor config"
sudo cp deploy/whatsapp-proxy.conf "$SUPERVISOR_CONF"
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start whatsapp-proxy || sudo supervisorctl restart whatsapp-proxy
echo "    ✓ Supervisor process started"

# ── Step 4: Nginx config ──────────────────────────────────────────────────────
echo "▶ [4/6] Installing Nginx config (HTTP only first)"
# Write HTTP-only block first so Certbot can validate the domain
sudo bash -c "cat > $NGINX_CONF" <<'EOF'
server {
    listen 80;
    server_name botmaster.storenxt.in;
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
sudo nginx -t && sudo systemctl reload nginx
echo "    ✓ Nginx config applied"

# ── Step 5: SSL via Certbot ───────────────────────────────────────────────────
echo "▶ [5/6] Obtaining SSL certificate for $DOMAIN"
echo "    (Make sure DNS A record for $DOMAIN points to this server's public IP first)"
echo ""
read -p "    DNS ready? Press ENTER to continue or Ctrl+C to abort..."
sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos \
    --email admin@storenxt.in --redirect
echo "    ✓ SSL certificate installed"

# ── Step 6: Final check ───────────────────────────────────────────────────────
echo "▶ [6/6] Running health check"
sleep 2
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/health" || echo "failed")
if [ "$STATUS" = "200" ]; then
    echo "    ✓ Health check passed (HTTP $STATUS)"
else
    echo "    ✗ Health check returned: $STATUS — check logs below"
    sudo supervisorctl status whatsapp-proxy
    echo ""
    echo "    Proxy logs:"
    tail -20 /var/log/whatsapp-proxy.err.log
fi

echo ""
echo "══════════════════════════════════════════"
echo "  Deployment Complete"
echo "  Proxy URL: https://$DOMAIN/api/v1/"
echo "  Swagger:   https://$DOMAIN/docs"
echo "  Health:    https://$DOMAIN/health"
echo "══════════════════════════════════════════"
echo ""
echo "Useful commands:"
echo "  sudo supervisorctl status whatsapp-proxy       # check process"
echo "  sudo supervisorctl restart whatsapp-proxy      # restart"
echo "  tail -f /var/log/whatsapp-proxy.out.log        # live logs"
echo "  tail -f /var/log/whatsapp-proxy.err.log        # error logs"
