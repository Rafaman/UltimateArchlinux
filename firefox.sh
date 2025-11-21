#!/bin/bash

# ==============================================================================
#  BROWSER HARDENING: ARKENFOX & FIREJAIL PURGE
# ==============================================================================
#  1. Installazione Firefox
#  2. Rimozione Firejail (Anti-Pattern)
#  3. Deployment automatico Arkenfox (user.js)
#  4. Configurazione Overrides (Bilanciamento Privacy/Usabilità)
#  5. Verifica Confinamento AppArmor
# ==============================================================================

# --- STILE ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

ICON_FOX="[🦊]"
ICON_GHOST="[👻]"
ICON_LOCK="[🔒]"
ICON_TRASH="[🗑️]"
ICON_WARN="[!]"
ICON_OK="[✔]"

# Rilevamento Utente Reale (Non root)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
FIREFOX_DIR="$USER_HOME/.mozilla/firefox"

# --- FUNZIONI ---

log_header() { echo -e "\n${PURPLE}${BOLD}:: $1${NC}"; }
log_success() { echo -e "${GREEN}${ICON_OK} $1${NC}"; }
log_info() { echo -e "${BLUE}${ICON_FOX} $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}Esegui come root (sudo).${NC}"
       exit 1
    fi
}

# --- MAIN ---

clear
echo -e "${RED}${BOLD}"
echo "     _   ___ _  _____ _  _ ___ _____  __ "
echo "    /_\ | _ \ |/ / __| \| | __/ _ \ \/ / "
echo "   / _ \|   / ' <| _|| .\` | _| (_) >  <  "
echo "  /_/ \_\_|_\_|\_\___|_|\_|_| \___/_/\_\ "
echo "       BROWSER HARDENING AUTOMATION      "
echo -e "${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Target User: ${BOLD}$REAL_USER${NC}"

check_root

# 1. GESTIONE FIREJAIL (IL RIFIUTO)
log_header "1. Verifica Conflitti (Firejail)"

if pacman -Qi firejail &> /dev/null; then
    echo -e "${RED}${ICON_WARN} Rilevato Firejail installato.${NC}"
    echo -e "La guida sconsiglia Firejail con i browser moderni (Swiss Cheese effect)."
    echo -e "Si consiglia di rimuoverlo per affidarsi a RLBox + AppArmor."
    echo ""
    echo -e -n "${BOLD}Vuoi rimuovere Firejail ora? (s/N): ${NC}"
    read -r resp
    if [[ "$resp" =~ ^([sS][iI]|[sS])$ ]]; then
        pacman -Rns --noconfirm firejail
        log_success "Firejail rimosso. Superficie di attacco ridotta."
    else
        echo -e "${YELLOW}Firejail mantenuto. Assicurati di NON usarlo con Firefox.${NC}"
    fi
else
    log_success "Firejail non presente. Ottimo."
fi

# 2. INSTALLAZIONE FIREFOX
log_header "2. Installazione Firefox"
if ! pacman -Qi firefox &> /dev/null; then
    log_info "Installazione pacchetto Firefox..."
    pacman -S --noconfirm firefox
    log_success "Firefox installato."
else
    log_success "Firefox è già presente."
fi

# 3. GENERAZIONE PROFILO
log_header "3. Inizializzazione Profilo"

# Verifica se esiste la cartella .mozilla/firefox
if [[ ! -d "$FIREFOX_DIR" ]]; then
    echo -e "   Cartella profilo mancante. Creazione headless..."
    # Eseguiamo firefox -CreateProfile come l'utente reale
    sudo -u "$REAL_USER" firefox --headless --CreateProfile "default-release" &> /dev/null
    sleep 2
fi

# Trova la cartella del profilo (quella che finisce con .default-release o .default)
PROFILE_PATH=$(find "$FIREFOX_DIR" -maxdepth 1 -type d -name "*.default-release" | head -n 1)

if [[ -z "$PROFILE_PATH" ]]; then
    # Fallback: prova .default
    PROFILE_PATH=$(find "$FIREFOX_DIR" -maxdepth 1 -type d -name "*.default" | head -n 1)
fi

if [[ -z "$PROFILE_PATH" ]]; then
    echo -e "${RED}Impossibile trovare il profilo Firefox. Avvia Firefox manualmente una volta e riprova.${NC}"
    exit 1
fi

echo -e "   Profilo rilevato: ${BOLD}$PROFILE_PATH${NC}"

# 4. DEPLOYMENT ARKENFOX
log_header "4. Installazione Arkenfox (user.js)"

# Scarica l'updater ufficiale nella cartella del profilo
UPDATER_URL="https://raw.githubusercontent.com/arkenfox/user.js/master/updater.sh"

echo -e "   Scaricamento updater script..."
sudo -u "$REAL_USER" curl -s -L -o "$PROFILE_PATH/updater.sh" "$UPDATER_URL"
sudo -u "$REAL_USER" chmod +x "$PROFILE_PATH/updater.sh"

# 5. CONFIGURAZIONE OVERRIDES (USABILITÀ)
log_header "5. Configurazione Overrides (user-overrides.js)"

OVERRIDES_FILE="$PROFILE_PATH/user-overrides.js"

echo -e "   Creazione eccezioni per usabilità quotidiana..."
# Scriviamo un file di override che l'utente può modificare
cat <<EOF > "$OVERRIDES_FILE"
/**
 * ARKENFOX OVERRIDES - Generato da Script Automazione
 * Scommenta le righe per abilitare le funzioni.
 */

/* --- SESSION RESTORE --- */
// Ripristina la sessione precedente all'avvio (Default Arkenfox: false)
// user_pref("browser.startup.page", 3);

/* --- DRM / NETFLIX / SPOTIFY --- */
// Abilita DRM (Widevine) per lo streaming legale (Default Arkenfox: false)
user_pref("media.eme.enabled", true);
user_pref("media.gmp-widevinecdm.visible", true);
user_pref("media.gmp-widevinecdm.enabled", true);

/* --- RICERCA DALLA BARRA DEGLI INDIRIZZI --- */
// Permette di cercare scrivendo nella barra URL (Default Arkenfox: false)
user_pref("keyword.enabled", true);

/* --- GEO-IP LOOKUP --- */
// Riduce il rumore se usi servizi che richiedono la zona approssimativa
// user_pref("geo.enabled", true);

EOF

chown "$REAL_USER":"$REAL_USER" "$OVERRIDES_FILE"
log_success "Overrides creati. Abilitato DRM e Ricerca URL per default."

# 6. ESECUZIONE UPDATER
log_header "6. Applicazione user.js"
echo -e "   Esecuzione Arkenfox updater (potrebbe richiedere qualche secondo)..."

cd "$PROFILE_PATH" || exit
# Eseguiamo l'updater come utente reale.
# -s: silent, -u: update user.js
if sudo -u "$REAL_USER" ./updater.sh -s -u; then
    log_success "Arkenfox applicato con successo!"
else
    echo -e "${RED}Errore durante l'applicazione di Arkenfox.${NC}"
fi

# 7. VERIFICA APPARMOR
log_header "7. Verifica Sicurezza Sistema (AppArmor)"

if command -v aa-status &> /dev/null; then
    if aa-status | grep -q "firefox"; then
        echo -e "${GREEN}${ICON_LOCK} Firefox è confinato da AppArmor.${NC}"
    else
        echo -e "${YELLOW}${ICON_WARN} Profilo AppArmor per Firefox non attivo
