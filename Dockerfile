FROM --platform=linux/amd64 ubuntu:22.04

# Evitar diálogos interactivos durante la instalación
ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias base + Nginx (Se eliminó snapd por incompatibilidad)
RUN apt update -y && apt install --no-install-recommends -y \
    xfce4 xfce4-goodies tigervnc-standalone-server novnc websockify \
    sudo xterm vim net-tools curl wget git tzdata openssl ca-certificates nginx jq

# 2. Configurar entorno de escritorio y Firefox vía PPA (Evita Snap)
RUN apt update -y && apt install -y dbus-x11 x11-utils x11-xserver-utils x11-apps software-properties-common
RUN add-apt-repository ppa:mozillateam/ppa -y

# Priorizar el PPA de Mozilla sobre el repositorio de Ubuntu para evitar snap
RUN echo 'Package: *' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox

RUN apt update -y && apt install -y firefox xubuntu-icon-theme
RUN touch /root/.Xauthority

# 3. Instalar PufferPanel via repositorio oficial
RUN curl -s https://packagecloud.io/install/repositories/pufferpanel/pufferpanel/script.deb.sh | bash && \
    apt-get install -y pufferpanel && \
    mkdir -p /etc/pufferpanel /var/lib/pufferpanel /var/log/pufferpanel

# --- PARCHE NO-VNC PARA RAILWAY/HTTPS ---
# Forzar a noVNC a detectar el puerto 443/80 externo en lugar del interno 6080
RUN sed -i "s/UI.initSetting('port', window.location.port);/UI.initSetting('port', window.location.port || (window.location.protocol === 'https:' ? 443 : 80));/g" /usr/share/novnc/app/ui.js

# 4. Configurar Nginx como Proxy Inverso
RUN echo 'server {\n\
    listen 80;\n\
\n\
    # Interfaz de PufferPanel\n\
    location / {\n\
        proxy_pass http://127.0.0.1:8080/;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "Upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
\n\
    # Escritorio VNC (Interfaz noVNC)\n\
    location /vnc/ {\n\
        proxy_pass http://127.0.0.1:6080/;\n\
    }\n\
\n\
    # WebSocket del VNC (Crítico para movimiento de ratón/teclado)\n\
    location /websockify {\n\
        proxy_pass http://127.0.0.1:6080/websockify;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade $http_upgrade;\n\
        proxy_set_header Connection "Upgrade";\n\
        proxy_set_header Host $host;\n\
    }\n\
}' > /etc/nginx/sites-available/default

# 5. Script de arranque robusto
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "[1/5] Limpiando bloqueos de sesiones previas..."\n\
rm -rf /tmp/.X11-unix/X* /tmp/.X*-lock /root/.vnc/*.pid /root/.vnc/*.log 2>/dev/null || true\n\
\n\
echo "[2/5] Iniciando VNC Server..."\n\
# Crear contraseña por defecto para evitar prompts (puffer123)\n\
mkdir -p /root/.vnc\n\
echo "puffer123" | vncpasswd -f > /root/.vnc/passwd\n\
chmod 600 /root/.vnc/passwd\n\
vncserver :1 -localhost no -geometry 1280x720 -SecurityTypes None --I-KNOW-THIS-IS-INSECURE\n\
\n\
echo "[3/5] Iniciando Websockify (puerto 6080)..."\n\
websockify --web=/usr/share/novnc/ 6080 localhost:5901 > /var/log/websockify.log 2>&1 &\n\
\n\
echo "[4/5] Configurando PufferPanel..."\n\
if [ ! -f /etc/pufferpanel/config.json ]; then\n\
    echo "{\n  \"panel\": {\n    \"web\": {\n      \"host\": \"0.0.0.0:8080\"\n    }\n  }\n}" > /etc/pufferpanel/config.json\n\
fi\n\
\n\
# IMPORTANTE: Cambiar al directorio de assets para que PufferPanel funcione correctamente\n\
cd /usr/share/pufferpanel\n\
export GIN_MODE=release\n\
# Crear admin por defecto si es necesario (Opcional)\n\
# /usr/sbin/pufferpanel user add --name admin --email admin@test.com --password password --admin true || true\n\
\n\
/usr/sbin/pufferpanel run > /var/log/pufferpanel/server.log 2>&1 &\n\
\n\
echo "[5/5] Iniciando Nginx y monitoreando logs..."\n\
tail -f /var/log/pufferpanel/server.log &\n\
nginx -g "daemon off;"\n' > /start.sh && chmod +x /start.sh

# 6. Exponer puerto 80 para Railway
EXPOSE 80

CMD ["/start.sh"]
