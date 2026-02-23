#!/bin/bash

# Activar control de trabajos de bash (necesario para manejar procesos en background)
set -m

echo "[INFO] Limpiando sockets VNC anteriores por si hubo un reinicio forzado..."
rm -rf /tmp/.X11-unix /tmp/.X1-lock 2>/dev/null || true

echo "[INFO] Iniciando VNC Server (Display :1)..."
# Arrancamos VNC. El proceso de vncserver se va a background automáticamente.
vncserver -localhost no -SecurityTypes None -geometry 1280x720 --I-KNOW-THIS-IS-INSECURE

echo "[INFO] Generando certificado SSL temporal para noVNC..."
openssl req -new -subj "/C=JP" -x509 -days 365 -nodes -out /self.pem -keyout /self.pem 2>/dev/null

echo "[INFO] Iniciando Websockify (noVNC en el puerto 6080)..."
# Lanzamos websockify en background usando &
websockify -D --web=/usr/share/novnc/ --cert=/self.pem 6080 localhost:5901 &

echo "[INFO] Verificando directorios de PufferPanel..."
mkdir -p /var/log/pufferpanel /var/lib/pufferpanel /etc/pufferpanel

echo "[INFO] Iniciando PufferPanel (Puerto 8080 y 5657)..."
# Lanzamos PufferPanel en background y guardamos su salida en un log
/usr/local/bin/pufferpanel run > /var/log/pufferpanel/server.log 2>&1 &

echo "=========================================================="
echo "✅ Todo iniciado correctamente."
echo "🖥️  Escritorio VNC: http://localhost:6080/vnc.html"
echo "🎮 Panel Puffer:  http://localhost:8080"
echo "=========================================================="

# Mantener el contenedor vivo mostrando los logs de PufferPanel en la consola
# Si PufferPanel se cae, nos daremos cuenta en los logs de Docker
tail -f /var/log/pufferpanel/server.log
