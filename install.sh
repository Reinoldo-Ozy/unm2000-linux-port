#!/bin/bash
set -e

# UNM2000 Linux Port — Instalador
# Requer: instalador original unm2000_Client_en.exe (licença FiberHome)
# Distribuição: patches de compatibilidade Linux, sem binários proprietários

INSTALL_DIR="/opt/unm2000"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patches"
EXTRAS_DIR="$SCRIPT_DIR/extras"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── Argumento ──────────────────────────────────────────────────────────────────
if [ -z "$1" ]; then
  echo "Uso: sudo $0 /caminho/para/unm2000_Client_en.exe"
  echo ""
  echo "  O instalador original deve ser obtido junto à FiberHome."
  echo "  Este script aplica patches de compatibilidade Linux sem"
  echo "  redistribuir os arquivos proprietários."
  exit 1
fi

INSTALLER="$(realpath "$1")"
[ -f "$INSTALLER" ] || error "Arquivo não encontrado: $INSTALLER"
[ "$EUID" -eq 0 ]   || error "Execute com sudo: sudo $0 $1"

echo ""
echo "  UNM2000 Linux Port — Instalador"
echo "  ================================"
echo ""

# ── Dependências ───────────────────────────────────────────────────────────────
check_dep() {
  command -v "$1" &>/dev/null
}

install_deps() {
  warn "Verificando dependências..."

  local need_unrar=0 need_bsdiff=0
  check_dep unrar   || need_unrar=1
  check_dep bspatch || need_bsdiff=1

  if [ $need_unrar -eq 1 ] || [ $need_bsdiff -eq 1 ]; then
    if check_dep apt-get; then
      [ $need_unrar  -eq 1 ] && apt-get install -y unrar
      [ $need_bsdiff -eq 1 ] && apt-get install -y bsdiff
    elif check_dep dnf; then
      [ $need_unrar  -eq 1 ] && dnf install -y unrar
      [ $need_bsdiff -eq 1 ] && dnf install -y bsdiff
    elif check_dep pacman; then
      [ $need_unrar  -eq 1 ] && pacman -S --noconfirm unrar
      [ $need_bsdiff -eq 1 ] && pacman -S --noconfirm bsdiff
    elif check_dep zypper; then
      [ $need_unrar  -eq 1 ] && zypper install -y unrar
      [ $need_bsdiff -eq 1 ] && zypper install -y bsdiff
    else
      error "Instale manualmente: unrar bsdiff"
    fi
  fi

  info "unrar e bspatch disponíveis"
}

check_java() {
  local java_bin=""

  for d in \
    /usr/lib/jvm/java-21-openjdk-amd64 \
    /usr/lib/jvm/java-21-openjdk \
    /usr/lib/jvm/temurin-21-jre-amd64 \
    /usr/lib/jvm/temurin-21-jre; do
    [ -x "$d/bin/java" ] && java_bin="$d" && break
  done

  if [ -z "$java_bin" ]; then
    warn "Java 21 não encontrado."
    echo ""
    echo "  Instale o Java 21 e execute novamente:"
    echo ""
    echo "  Debian/Ubuntu:"
    echo "    wget -qO /etc/apt/trusted.gpg.d/adoptium.asc https://packages.adoptium.net/artifactory/api/gpg/key/public"
    echo "    echo 'deb https://packages.adoptium.net/artifactory/deb \$(. /etc/os-release && echo \$VERSION_CODENAME) main' > /etc/apt/sources.list.d/adoptium.list"
    echo "    apt-get update && apt-get install -y temurin-21-jre"
    echo ""
    echo "  RHEL/Fedora:"
    echo "    dnf install -y temurin-21-jre (após adicionar repo Adoptium)"
    echo ""
    echo "  Arch:"
    echo "    pacman -S jre21-openjdk"
    echo ""
    exit 1
  fi

  info "Java 21 encontrado: $java_bin" >&2
  echo "$java_bin"
}

# ── Extração completa do instalador ───────────────────────────────────────────
extract_installer() {
  local tmpdir="$1"
  info "Extraindo instalador (pode demorar alguns minutos)..."

  unrar x -o+ "$INSTALLER" "unm2000/*" "$tmpdir/" > /dev/null 2>&1 || true

  local extracted
  extracted=$(find "$tmpdir/unm2000" -name "*.jar" -size +0c 2>/dev/null | wc -l)
  [ "$extracted" -gt 10 ] || error "Extração falhou. Verifique se o instalador é o unm2000_Client_en.exe original."
  info "$extracted JARs extraídos"
}

# ── Copia estrutura completa do app ───────────────────────────────────────────
copy_app() {
  local tmpdir="$1"
  info "Copiando arquivos do app..."

  cp -r "$tmpdir/unm2000/." "$INSTALL_DIR/app/"

  # Substitui a conf Windows pela versão Linux com flags de compatibilidade
  cp "$EXTRAS_DIR/unm2000access.conf.template" "$INSTALL_DIR/app/etc/unm2000access.conf"
}

# ── Aplica patches de compatibilidade Linux ───────────────────────────────────
apply_patches() {
  local tmpdir="$1"
  local total
  total=$(find "$PATCH_DIR" -name "*.bsdiff" | wc -l)
  info "Aplicando $total patches de compatibilidade Linux..."

  find "$PATCH_DIR" -name "*.bsdiff" | while read -r patch; do
    rel="${patch#$PATCH_DIR/}"
    rel="${rel%.bsdiff}"
    orig="$tmpdir/unm2000/$rel"
    target="$INSTALL_DIR/app/$rel"

    [ -f "$orig" ] || { warn "Não encontrado: $rel (versão do instalador diferente?)"; continue; }
    mkdir -p "$(dirname "$target")"
    bspatch "$orig" "$target" "$patch"
  done

  info "Patches aplicados"
}

# ── Instalação ─────────────────────────────────────────────────────────────────
main() {
  install_deps
  local java_home
  java_home=$(check_java)

  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT

  mkdir -p "$INSTALL_DIR/app" "$INSTALL_DIR/lib"

  extract_installer "$tmpdir"
  copy_app "$tmpdir"
  apply_patches "$tmpdir"

  # Libs extras do port
  cp "$EXTRAS_DIR/hookagent.jar"  "$INSTALL_DIR/lib/"
  cp "$EXTRAS_DIR/activation.jar" "$INSTALL_DIR/lib/"
  cp "$EXTRAS_DIR/activation.jar" "$INSTALL_DIR/app/unmplatform/modules/ext/"

  # Configura jdkhome com o Java 21 detectado
  sed -i "s|^jdkhome=.*|jdkhome=\"$java_home\"|" "$INSTALL_DIR/app/etc/unm2000access.conf"

  # Launcher
  cat > /usr/local/bin/unm2000 << 'EOF'
#!/bin/bash
for d in \
    /usr/lib/jvm/java-21-openjdk-amd64 \
    /usr/lib/jvm/java-21-openjdk \
    /usr/lib/jvm/temurin-21-jre-amd64 \
    /usr/lib/jvm/temurin-21-jre; do
  if [ -x "$d/bin/java" ]; then
    CURRENT=$(grep '^jdkhome=' /opt/unm2000/app/etc/unm2000access.conf | cut -d'"' -f2)
    [ "$CURRENT" != "$d" ] && sed -i "s|^jdkhome=.*|jdkhome=\"$d\"|" /opt/unm2000/app/etc/unm2000access.conf
    break
  fi
done
cd /opt/unm2000/app
exec bin/unm2000access
EOF
  chmod +x /usr/local/bin/unm2000

  # Desktop entry
  cat > /usr/share/applications/unm2000.desktop << 'EOF'
[Desktop Entry]
Name=UNM2000
Comment=FiberHome NMS Client
Exec=unm2000
Icon=/opt/unm2000/app/unm2000access/config/branding/images/product.png
Terminal=false
Type=Application
Categories=Network;
EOF

  chmod -R a+rX "$INSTALL_DIR"
  chmod -R u+w  "$INSTALL_DIR"

  echo ""
  info "UNM2000 instalado com sucesso!"
  info "Na primeira execução o NetBeans reconstrói o cache (~2-5 min). As seguintes são rápidas."
  info "Execute: unm2000"
  echo ""
}

main
