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
| `platform/lib/org-openide-util-lookup.jar` | `ActiveQueue$Impl.removeSuper()` → timeout > 0 (fix CPU 100%, ver v1.1) |
| `unmplatform/modules/com-fiberhome-core.jar` | `SystemExitAction.exit/exitNormal` reconstruídos (fix saída travada, ver v1.1); `ExitUtils.exitToLogin()` → no-op; `matchVersion()` → sempre true |
| `unmplatform/modules/com-fiberhome-authentication.jar` | Callbacks de heartbeat → no-op (evitam crash ao expirar sessão ICE) |
| `unmplatform/modules/com-fiberhome-component.jar` | `WindowsComboBoxUI` → `MetalComboBoxUI` (classe inexistente no Linux/OpenJDK) |
| `unmplatform/modules/ext/jide-common.jar` | Shim de `sun.swing.plaf.synth.SynthIcon` (fix tela cinza, ver v1.1) |
| `unmplatform/modules/ext/Ice.jar` | `halt()` → `goto` (ZeroC ICE matava o JVM em timeouts de rede) |
| `unmplatform/modules/ext/IceGridGUI.jar` | idem |
| `unmplatform/modules/ext/Freeze.jar` | idem |
| `unmplatform/modules/ext/fcache.jar` | idem |

Os patches são distribuídos no formato **bsdiff** — requerem o JAR original para serem aplicados e não contêm nenhum byte proprietário por si só.

---

## Changelog

### v1.1 (2026-06-10)

Quatro correções validadas em produção:

- **CPU 100% constante** — Thread `ActiveQueue$Impl` (NetBeans platform) entrava em spin infinito no JDK 19+ porque `ReferenceQueue.remove(0)` passou a delegar para o método virtual sobrescrito. Patch usa `super.remove(86400000L)` para evitar a delegação. (`platform/lib/org-openide-util-lookup.jar`)
- **App não fechava após confirmar saída** — `SystemExitAction.exit()` e `exitNormal()` ficaram vazios no pipeline original. Classes reconstruídas com `LifecycleManager.exit()` + watchdog `Runtime.halt(0)` em 15s. (`unmplatform/modules/com-fiberhome-core.jar`)
- **Resource → Query → Query ONU não abria** — `InaccessibleObjectException` em `BasicComboBoxUI.arrowButton` + `IllegalAccessError` em `sun.jvmstat.monitor`. Resolvido por flags JPMS no `unm2000access.conf`:
  - `--add-opens=java.desktop/javax.swing.plaf.basic=ALL-UNNAMED`
  - `--add-exports=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED`
- **Tela cinza/sobreposta ao ordenar coluna** — JIDE pintava seta de ordenação usando `sun.swing.plaf.synth.SynthIcon`, classe interna removida no JDK 9+. Adicionado shim com a classe abstrata do JDK 8 ao `jide-common.jar`.

Outras mudanças:
- `_JAVA_AWT_WM_NONREPARENTING=1` exportado no launcher (corrige dialogs invisíveis em i3/sway).
- `chmod +x` explícito em `app/bin/unm2000access` (unrar removia o bit).

### v1.0 (2026-06-01)

Lançamento inicial: 8 patches bsdiff cobrindo SecurityManager, ICE, Freeze/fcache, WindowsComboBoxUI e métodos `exit*`/`matchVersion`.

---

## Notas

A engenharia reversa dos patches, análise de bytecode, investigação das incompatibilidades com Java 21 e desenvolvimento do instalador foram feitos com o auxílio do [Claude Code](https://claude.ai/code) (Anthropic).
