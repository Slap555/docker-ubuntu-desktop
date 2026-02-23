FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias base + Nginx como proxy interno
RUN apt update -y && apt install --no-install-recommends -y \
    xfce4 xfce4-goodies tigervnc-standalone-server novnc websockify \
    sudo xterm snapd vim net-tools curl wget git tzdata openssl ca-certificates nginx

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

# 4. Configurar Nginx como proxy inverso unico
# Railway solo expone 1 puerto publico. Nginx escucha en ese puerto
# y redirige /vnc -> websockify:6080 (VNC) y /panel -> pufferpanel:8080
RUN echo 'server {\n\
    listen 80;\n\
\n\
    # Pagina principal -> redirige al VNC\n\
    location / {\n\
        return 301 /vnc/vnc.html;\n\
    }\n\
\n\
    # Escritorio VNC (archivos estaticos de noVNC)\n\
    location /vnc/ {\n\
        proxy_pass http://127.0.0.1:6080/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Host $host;\n\
    }\n\
\n\
    # WebSocket del VNC (CRITICO para que noVNC conecte)\n\
    location /websockify {\n\
        proxy_pass http://127.0.0.1:6080/websockify;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "Upgrade";\n\
        proxy_set_header Host $host;\n\
        proxy_read_timeout 3600s;\n\
        proxy_send_timeout 3600s;\n\
    }\n\
\n\
    # Panel PufferPanel\n\
    location /panel/ {\n\
        proxy_pass http://127.0.0.1:8080/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "Upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
}' > /etc/nginx/sites-available/default

# 5. Script de arranque
RUN printf '#!/bin/bash\n\
set -e\n\
\n\
echo "[1/4] Limpiando locks VNC anteriores..."\n\
rm -rf /tmp/.X11-unix/X1 /tmp/.X1-lock 2>/dev/null || true\n\
\n\
echo "[2/4] Iniciando VNC Server..."\n\
vncserver -localhost no -SecurityTypes None -geometry 1280x720 --I-KNOW-THIS-IS-INSECURE\n\
\n\
echo "[3/4] Iniciando Websockify (sin SSL, Nginx es el proxy)..."\n\
websockify -D --web=/usr/share/novnc/ 6080 localhost:5901\n\
\n\
echo "[4/4] Iniciando PufferPanel..."\n\
PUFFER_BIN=$(which pufferpanel 2>/dev/null || echo "/usr/sbin/pufferpanel")\n\
$PUFFER_BIN run > /var/log/pufferpanel/server.log 2>&1 &\n\
\n\
echo "[5/5] Iniciando Nginx (proxy publico en puerto 80)..."\n\
nginx -g "daemon off;"\n' > /start.sh && chmod +x /start.sh

# 6. Solo exponemos el puerto de Nginx (Railway solo necesita 1)
EXPOSE 80

CMD ["/start.sh"]
