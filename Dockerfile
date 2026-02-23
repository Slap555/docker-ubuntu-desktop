FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 1. Instalar dependencias (quitamos systemd de la lista crítica, aunque se instale por deps)
RUN apt update -y && apt install --no-install-recommends -y \
    xfce4 xfce4-goodies tigervnc-standalone-server novnc websockify \
    sudo xterm snapd vim net-tools curl wget git tzdata openssl ca-certificates

# 2. Configurar entorno de escritorio y Firefox (parte original de Slap555)
RUN apt update -y && apt install -y dbus-x11 x11-utils x11-xserver-utils x11-apps
RUN apt install software-properties-common -y
RUN add-apt-repository ppa:mozillateam/ppa -y
RUN echo 'Package: *' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox
RUN apt update -y && apt install -y firefox xubuntu-icon-theme
RUN touch /root/.Xauthority

# 3. INSTALAR PUFFERPANEL (Sin usar apt/systemd)
# Descargamos el binario directo. Es más limpio para Docker.
RUN wget -q https://github.com/PufferPanel/PufferPanel/releases/latest/download/pufferpanel_linux_amd64 -O /usr/local/bin/pufferpanel \
    && chmod +x /usr/local/bin/pufferpanel

# Crear carpetas necesarias
RUN mkdir -p /etc/pufferpanel /var/lib/pufferpanel /var/log/pufferpanel

# 4. SCRIPT DE ARRANQUE (Reemplaza a systemd)
# Este script levanta VNC, luego Websockify, y finalmente PufferPanel en background
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "[INFO] Iniciando VNC..."\n\
vncserver -localhost no -SecurityTypes None -geometry 1280x720 --I-KNOW-THIS-IS-INSECURE\n\
\n\
echo "[INFO] Generando certificado SSL..."\n\
openssl req -new -subj "/C=JP" -x509 -days 365 -nodes -out /self.pem -keyout /self.pem 2>/dev/null\n\
\n\
echo "[INFO] Iniciando noVNC (Puerto 6080)..."\n\
websockify -D --web=/usr/share/novnc/ --cert=/self.pem 6080 localhost:5901\n\
\n\
echo "[INFO] Iniciando PufferPanel (Puerto 8080)..."\n\
# Ejecución manual en background\n\
/usr/local/bin/pufferpanel run > /var/log/pufferpanel/server.log 2>&1 &\n\
\n\
echo "[OK] Todo listo. Logs en /var/log/pufferpanel/server.log"\n\
tail -f /var/log/pufferpanel/server.log' > /start.sh && chmod +x /start.sh

# 5. Exponer Puertos
EXPOSE 6080 8080 5657

# 6. Arrancar
CMD ["/start.sh"]
