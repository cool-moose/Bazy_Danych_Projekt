#!/bin/bash

DB_NAME="db_projekt"
DB_USER="postgres"
ADMIN_EMAIL="admin@hotel.com"
ADMIN_PASSWORD="admin"

# Ścieżki
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR=${SCRIPT_DIR}
PROJECT_DIR=${SETUP_DIR}
APP_DIR="$PROJECT_DIR/BD_App"

# Kolory
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0;m' # No Color
BOLD='\033[;1m'


# FUNKCJE POMOCNICZE
status() { echo -e "  ${GREEN}:)${NC} $1"; }
error() { echo -e "  ${RED}X${NC} $1"; exit 1; }
warning() { echo -e "  ${YELLOW}!${NC} $1"; }
step() { echo -e "\n${YELLOW}[$1]${NC} $2"; }

step "1/5" "Sprawdzanie wymagań..."

# Python
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    status "Python: $PYTHON_VERSION"
else
    error "Python3 nie jest zainstalowany! Zainstaluj: sudo apt install python3 python3-pip python3-venv"
fi

# PostgreSQL
if command -v psql &> /dev/null; then
    status "PostgreSQL (psql) dostępny"
else
    error "PostgreSQL nie jest zainstalowany! Zainstaluj: sudo apt install postgresql postgresql-contrib"
fi

# Sprawdź czy PostgreSQL działa
if systemctl is-active --quiet postgresql 2>/dev/null; then
    status "PostgreSQL uruchomiony"
elif pgrep -x "postgres" > /dev/null; then
    status "PostgreSQL uruchomiony (bez systemd)"
else
    warning "PostgreSQL może nie być uruchomiony. Uruchamiam..."
    sudo systemctl start postgresql 2>/dev/null || true
fi

step "2/5" "Instalacja zależności Python..."

VENV_PATH="$PROJECT_DIR/venv"
REQUIREMENTS_PATH="$APP_DIR/requirements.txt"

# Utwórz venv jeśli nie istnieje
if [ ! -d "$VENV_PATH" ]; then
    echo "Tworzenie środowiska wirtualnego..."
    python3 -m venv "$VENV_PATH"
fi

# Aktywuj venv i zainstaluj zależności
source "$VENV_PATH/bin/activate"
pip install --upgrade pip -q 2>/dev/null
pip install -r "$REQUIREMENTS_PATH" -q 2>/dev/null

status "Zależności zainstalowane"

step "3/5" "Przeładowywanie bazy danych..."

# 3.1 Usuń starą bazę
echo "Usuwanie starej bazy '$DB_NAME'..."
sudo psql -U postgres -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" 2>/dev/null || true

# 3.2 Utwórz nową bazę
echo "Tworzenie nowej bazy..."
sudo psql -U postgres -c "CREATE DATABASE \"$DB_NAME\";" 2>/dev/null || error "Nie można utworzyć bazy danych"
status "Baza danych '$DB_NAME' utworzona"

# 3.3 Import struktury z baza.sql
echo "Importowanie struktury z baza.sql..."
sudo psql -U postgres -d "$DB_NAME" -f "$PROJECT_DIR/baza.sql"


echo ""
echo "Otwórz w przeglądarce: http://localhost:5000"
echo ""
echo -e "Login:  $ADMIN_EMAIL"
echo -e "Hasło:  $ADMIN_PASSWORD"
echo ""
echo "Naciśnij Ctrl+C aby zatrzymać serwer"
echo ""
echo ""

cd "$APP_DIR"
python3 app.py
