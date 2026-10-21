#!/bin/bash
# Amorçage : installe les prérequis, récupère Tracker-ANEF et lance install.sh.
# Usage : bash -c "$(curl -fsSL https://raw.githubusercontent.com/Guiza4/Import-Tools/main/bootstrap.sh)"
# Pas de `curl | bash` : stdin serait le script, or `gh auth login` a besoin du clavier.
set -euo pipefail

ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]; }
swift_v() { swift --version 2>&1 | sed -n 's/.*Swift version \([0-9][0-9.]*\).*/\1/p' | head -1; }
swift_ok() { local v; v="$(swift_v)"; [[ -n "$v" ]] && ge "$v" 6.2; }
die() { echo "$*" >&2; exit 1; }

echo "1. Vérification de macOS…"
v="$(sw_vers -productVersion)"
ge "$v" 15.6 || die "macOS $v trouvé, 15.6 minimum requis : Réglages Système > Mise à jour de logiciels."

echo "2. Outils Apple…"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  echo "Installez les outils Apple dans la fenêtre ouverte : la suite reprendra seule."
  until xcode-select -p >/dev/null 2>&1; do sleep "${BOOTSTRAP_SLEEP:-5}"; done
fi

echo "3. Swift 6.2 minimum…"
if ! swift_ok; then
  # shortcut: format du label deviné (« Xcode-26.0 » ou « Xcode 26.0-26.0 »), à revoir si Apple le change
  label="$(softwareupdate --list 2>&1 | sed -n 's/^[* ]*Label: \(Command Line Tools for Xcode[- ]\([0-9][0-9.]*\).*\)$/\2|\1/p' | sort -V | tail -1 | cut -d'|' -f2-)"
  [[ -n "$label" ]] || die "Aucune mise à jour des outils Apple disponible : mettez macOS à jour, puis relancez."
  echo "Installation de « $label » (plusieurs Go, mot de passe administrateur demandé)…"
  sudo softwareupdate -i "$label"
  swift_ok || die "Swift est toujours inférieur à 6.2 : mettez macOS à jour, puis relancez."
fi

echo "4. GitHub CLI…"
if ! command -v gh >/dev/null; then
  # Homebrew fraîchement installé n'est pas dans le PATH tant que les « Next steps » n'ont pas été faits.
  find_brew() {
    brew=$(command -v brew || true)
    [[ -n "$brew" ]] && return 0
    IFS=: read -ra cands <<< "${BOOTSTRAP_BREW_PATHS:-/opt/homebrew/bin/brew:/usr/local/bin/brew}"
    for b in "${cands[@]}"; do [[ -x "$b" ]] && { brew=$b; eval "$("$b" shellenv)"; return 0; }; done
    return 1
  }
  if ! find_brew; then
    echo "Homebrew est absent : installation (le mot de passe administrateur de ce Mac sera demandé)…"
    if [[ -n "${BOOTSTRAP_BREW_INSTALLER:-}" ]]; then "$BOOTSTRAP_BREW_INSTALLER" || true
    else /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true; fi
    find_brew || die "L'installation de Homebrew a échoué (compte administrateur requis) : installez-le depuis https://brew.sh puis relancez."
  fi
  "$brew" install gh
fi

echo "5. Connexion GitHub…"
gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
gh auth setup-git

echo "6. Récupération de Tracker-ANEF…"
dest="$HOME/Tracker-ANEF"
if [[ -d "$dest" ]]; then
  # Dossier préexistant : ne lancer son install.sh que s'il vient bien du dépôt officiel.
  origin="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
  [[ "$origin" =~ github\.com[:/]Guiza4/Tracker-ANEF(\.git)?$ ]] \
    || die "$dest ne provient pas de Guiza4/Tracker-ANEF (origin : ${origin:-aucune}) : renommez ce dossier, puis relancez."
  git -C "$dest" pull
else
  gh repo clone Guiza4/Tracker-ANEF "$dest"
fi

echo "7. Installation…"
cd "$dest"
./install.sh
