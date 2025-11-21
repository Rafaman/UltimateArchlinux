#!/bin/bash

# ==============================================================================
#  SNAPPER ROLLBACK FIXER (AMBIT ERROR)
# ==============================================================================
#  Risolve l'errore: "Cannot detect ambit since default subvolume is unknown"
#  Imposta il subvolume corrente (@) come Btrfs Default.
# ==============================================================================

BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}:: Diagnostica Snapper Ambit...${NC}"

# 1. Trova l'ID del subvolume @ (Root)
# Cerca nella lista dei subvolumi quello che si chiama esattamente "@"
ROOT_ID=$(sudo btrfs subvolume list / | grep -E "path @$" | awk '{print $2}')

if [[ -z "$ROOT_ID" ]]; then
    # Fallback: prova a vedere se è montato come root
    ROOT_ID=$(sudo btrfs subvolume show / | grep "Subvolume ID:" | awk '{print $3}')
fi

if [[ -z "$ROOT_ID" ]]; then
    echo -e "${RED}Errore: Impossibile trovare l'ID del subvolume @.${NC}"
    exit 1
fi

echo -e "   ID Subvolume @ rilevato: ${BOLD}$ROOT_ID${NC}"

# 2. Controlla il default attuale
CURRENT_DEFAULT=$(sudo btrfs subvolume get-default / | awk '{print $2}')
echo -e "   ID Default attuale: $CURRENT_DEFAULT"

# 3. Applica il Fix
if [[ "$ROOT_ID" == "$CURRENT_DEFAULT" ]]; then
    echo -e "${GREEN}   [OK] Il default è già corretto. L'errore potrebbe essere altrove.${NC}"
else
    echo -e "   Impostazione ID $ROOT_ID come default di sistema..."
    sudo btrfs subvolume set-default "$ROOT_ID" /
    
    # Verifica
    NEW_DEFAULT=$(sudo btrfs subvolume get-default / | awk '{print $2}')
    if [[ "$NEW_DEFAULT" == "$ROOT_ID" ]]; then
        echo -e "${GREEN}   [OK] Fix applicato con successo.${NC}"
        echo -e "   Ora 'snapper rollback' dovrebbe funzionare."
    else
        echo -e "${RED}   [ERR] Impossibile impostare il default.${NC}"
    fi
fi
