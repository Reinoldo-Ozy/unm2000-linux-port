# UNM2000 Linux Port

Roda o cliente **UNM2000** (FiberHome NMS) nativamente no Linux com Java 21, sem Wine.

> **Requer o instalador original** `unm2000_Client_en.exe` obtido junto à FiberHome.  
> Este repositório contém apenas patches de compatibilidade Linux — nenhum arquivo proprietário é redistribuído.

---

## Requisitos

| Requisito | Versão |
|---|---|
| Java 21 JRE | `openjdk-21-jre` ou Temurin 21 |
| unrar | qualquer versão recente |
| bsdiff | qualquer versão recente |
| Instalador original | `unm2000_Client_en.exe` (FiberHome) |

---

## Instalação

```bash
sudo bash install.sh /caminho/para/unm2000_Client_en.exe
```

Na primeira execução o NetBeans reconstrói o cache de módulos (~2-5 min). As seguintes são rápidas.

### Java 21 — como instalar

**Debian/Ubuntu:**
```bash
wget -qO /etc/apt/trusted.gpg.d/adoptium.asc https://packages.adoptium.net/artifactory/api/gpg/key/public
echo "deb https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" \
  > /etc/apt/sources.list.d/adoptium.list
apt-get update && apt-get install -y temurin-21-jre
```

**RHEL/Fedora:**
```bash
dnf install -y temurin-21-jre  # após adicionar repo Adoptium
```

**Arch:**
```bash
pacman -S jre21-openjdk
```

---

## Uso

```bash
unm2000
```

Ou pelo menu de aplicativos (atalho `.desktop` criado automaticamente).

**Workspace por usuário:** `~/.unm2000access/dev/`

---

## OLTs testadas

| Modelo | Resultado |
|---|---|
| AN5116-06B | ✅ Funcional |
| AN5516-04 | ✅ Funcional |

Funcionalidades testadas: login, janela principal, NE Manager, OptModule.

---

## Limitações conhecidas

| Limitação | Descrição |
|---|---|
| **Java 21 apenas** | Outras versões não foram validadas |
| **amd64 apenas** | ARM requer reempacotar com `jdkhome` apontando para java-21 ARM |
| **Sem áudio** | Alertas sonoros dependem de PulseAudio configurado |
| **Sem JxBrowser** | Painéis com componente web interno ficam em branco |
| **Limite de janelas** | O app limita NE Managers abertas simultaneamente |

---

## Como funciona

O UNM2000 é uma aplicação **NetBeans Platform** em Java. O instalador Windows vem com JRE 8 bundled e usa APIs específicas do Windows. Os patches aplicados por este script corrigem incompatibilidades com Java 21 no Linux:

| JAR | Patch |
|---|---|
| `platform/lib/boot.jar` | `TopSecurityManager.install()` → no-op (Java 21 removeu `setSecurityManager`) |
| `unmplatform/modules/com-fiberhome-core.jar` | Métodos `exit()`/`exitNormal()`/`exitToLogin()` → no-op; `matchVersion()` → sempre true |
| `unmplatform/modules/com-fiberhome-authentication.jar` | Callbacks de heartbeat → no-op (evitam crash ao expirar sessão ICE) |
| `unmplatform/modules/com-fiberhome-component.jar` | `WindowsComboBoxUI` → `MetalComboBoxUI` (classe inexistente no Linux/OpenJDK) |
| `unmplatform/modules/ext/Ice.jar` | `halt()` → `goto` (ZeroC ICE matava o JVM em timeouts de rede) |
| `unmplatform/modules/ext/IceGridGUI.jar` | idem |
| `unmplatform/modules/ext/Freeze.jar` | idem |
| `unmplatform/modules/ext/fcache.jar` | idem |

Os patches são distribuídos no formato **bsdiff** — requerem o JAR original para serem aplicados e não contêm nenhum byte proprietário por si só.
