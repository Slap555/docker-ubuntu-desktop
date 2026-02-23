FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias base + Nginx
RUN apt update -y && apt install --no-install-recommends -y \
    xfce4 xfce4-goodies tigervnc-standalone-server novnc websockify \
    sudo xterm snapd vim net-tools curl wget git tzdata openssl ca-certificates nginx jq

# 2. Configurar entorno de escritorio y Firefox
RUN apt update -y && apt install -y dbus-x11 x11-utils x11-xserver-utils x11-apps
RUN apt install software-properties-common -y
RUN add-apt-repository ppa:mozillateam/ppa -y
RUN echo 'Package: *' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
RUN apt update -y && apt install -y firefox xubuntu-icon-theme
RUN touch /root/.Xauthority

# 3. Instalar PufferPanel via repositorio APT
RUN curl -s https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh | bash
RUN apt-get install -y pufferpanel
RUN mkdir -p /etc/pufferpanel /var/lib/pufferpanel /var/log/pufferpanel

# --- PARCHE NO-VNC Y RAILWAY ---
RUN sed -i "s/UI.initSetting('port', window.location.port);/UI.initSetting('port', window.location.port || (window.location.protocol === 'https:' ? 443 : 80));/g" /usr/share/novnc/app/ui.js

# 4. Configurar Nginx proxy
RUN echo 'server {\n\
    listen 80;\n\
\n\
    location /vnc/ {\n\
        proxy_pass http://127.0.0.1:6080/;\n\
    }\n\
\n\
    location /websockify {\n\
        proxy_pass http://127.0.0.1:6080/websockify;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "Upgrade";\n\
    }\n\
\n\
    location / {\n\
        proxy_pass http://127.0.0.1:8080/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "Upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
}' > /etc/nginx/sites-available/default

# 5. Script de arranque
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "[1/4] Iniciando VNC..."\n\
rm -rf /tmp/.X11-unix/X1 /tmp/.X1-lock 2>/dev/null || true\n\
vncserver -localhost no -SecurityTypes None -geometry 1280x720 --I-KNOW-THIS-IS-INSECURE\n\
\n\
echo "[2/4] Preparando logs y Websockify..."\n\
# IMPORTANTE: Creamos los archivos manualmente primero para que tail no falle\n\
mkdir -p /var/log/pufferpanel /var/log/nginx\n\
touch /var/log/pufferpanel/server.log /var/log/websockify.log /var/log/nginx/error.log\n\
chmod 777 /var/log/pufferpanel/server.log\n\
\n\
websockify --web=/usr/share/novnc/ 6080 localhost:5901 > /var/log/websockify.log 2>&1 &\n\
\n\
echo "[3/4] Inicializando configuración de PufferPanel..."\n\
if [ ! -f /etc/pufferpanel/config.json ]; then\n\
    echo "{\n  \"panel\": {\n    \"web\": {\n      \"host\": \"0.0.0.0:8080\"\n    }\n  }\n}" > /etc/pufferpanel/config.json\n\
fi\n\
chown -R root:root /etc/pufferpanel /var/lib/pufferpanel /var/log/pufferpanel\n\
\n\
echo "[4/4] Iniciando PufferPanel..."\n\
PUFFER_BIN=$(which pufferpanel 2>/dev/null || echo "/usr/sbin/pufferpanel")\n\
PUFFER_PANEL_WEB_HOST=0.0.0.0:8080 $PUFFER_BIN run > /var/log/pufferpanel/server.log 2>&1 &\n\
\n\
echo "[5/5] Iniciando Nginx..."\n\
# Ahora tail encontrara los archivos garantizado\n\
tail -f /var/log/pufferpanel/server.log &\n\
\n\
nginx -g "daemon off;"\n' > /start.sh && chmod +x /start.sh


# 6. Solo exponemos el puerto de Nginx 
EXPOSE 80

CMD ["/start.sh"]
