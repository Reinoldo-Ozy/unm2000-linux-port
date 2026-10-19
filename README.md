# UNM2000 Linux Port

Roda o cliente **UNM2000** (FiberHome NMS) nativamente no Linux com Java 21, sem Wine.

**Em uso diário em produção desde junho/2026** gerenciando OLTs FiberHome em um provedor real.

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

**Debian 13 (Trixie) ou mais novo** — direto dos repositórios oficiais:
```bash
apt-get install -y openjdk-21-jre
```

**Debian 12 / Ubuntu antigos** — via Adoptium:
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

**Funcionalidades validadas em produção:** login, janela principal, NE Manager (múltiplas janelas simultâneas), OptModule, Query ONU (Resource → Query), ONU List com ordenação por coluna, sumário e painel de alarmes, configuração de serviço.

---

## Limitações conhecidas

| Limitação | Descrição |
|---|---|
| **Java 21 apenas** | Outras versões não foram validadas |
| **amd64 apenas** | ARM requer reempacotar com `jdkhome` apontando para java-21 ARM |
| **Sem áudio** | Alertas sonoros dependem de PulseAudio configurado |
| **Sem JxBrowser** | O componente web embutido (Chromium via JxBrowser) falha ao extrair `chromium-linux64.7z` na inicialização; painéis que dependem dele não renderizam. Não afeta a operação normal (NE Manager, ONUs, alarmes) |

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
| `unmplatform/modules/com-fiberhome-busclient.jar` | `IceHelper.findClass` → fallback multi-classloader (fix diálogo "RPC request can't be decoded" no 1º login do dia, ver v1.3) |
| `unmplatform/modules/ext/jide-common.jar` | Shims de `sun.swing.plaf.synth.SynthIcon` (fix tela cinza, ver v1.1) e `com.sun.java.swing.plaf.windows.WindowsLookAndFeel` (fix repaint de styled labels, ver v1.2) |
| `unmplatform/modules/ext/Ice.jar` | `halt()` → `goto` (ZeroC ICE matava o JVM em timeouts de rede) |
| `unmplatform/modules/ext/IceGridGUI.jar` | idem |
| `unmplatform/modules/ext/Freeze.jar` | idem |
| `unmplatform/modules/ext/fcache.jar` | idem |

Os patches são distribuídos no formato **bsdiff** — requerem o JAR original para serem aplicados e não contêm nenhum byte proprietário por si só.

### Consumo de memória

O conf original da FiberHome fixava `-Xms512m`, prendendo 512 MB de heap para sempre (o live set real do app é ~150 MB). O template atual usa heap elástico:

- `-Xms128m -Xmx1024m` — piso baixo, teto preservado para queries grandes
- `-XX:G1PeriodicGCInterval=300000` — devolve heap ocioso ao sistema a cada 5 min
- `-XX:MinHeapFreeRatio=10 -XX:MaxHeapFreeRatio=30` + `-XX:+UseStringDeduplication` + `-XX:ReservedCodeCacheSize=96m`

**Resultado medido:** RSS de 787 MB → 580 MB (−26%), swap do processo de 151 MB → 0.

Instalações existentes: reaplicar o template em `/opt/unm2000/app/etc/unm2000access.conf` (ou editar os flags manualmente) — não requer limpar cache.

---

## Changelog

### v1.3 (2026-10-19)

- **Diálogo "The services are forwarded transparently (the RPC request can't be decoded)" no 1º login do dia** — `IceHelper.findClass` (em `com-fiberhome-busclient.jar`) resolve classes das respostas RPC usando **apenas o TCCL da thread**. Na primeira execução do dia o pool do SwingWorker ainda tem `MainImpl$BootClassLoader` como TCCL, e pacotes publicados entre módulos (ex.: `unmapi.security.*`) não aparecem no search path → `ClassNotFoundException` → o cliente converte em erro ICE 9 e mostra o diálogo; no 2º login o pool já está aquecido e funciona. Patch adiciona cache de classes + fallback: loader do próprio módulo → classloaders dos módulos NetBeans (`Modules.findCodeNameBase`). Comportamento normal inalterado (caminho TCCL continua o primeiro).
- Requer limpar `~/.unm2000access/dev/var/cache` após atualizar o jar (patch em jar de módulo).

### v1.2 (2026-07-14)

- **Tuning de consumo de RAM** — heap elástico no `unm2000access.conf` (ver seção acima). RSS −26% medido em produção.
- **NoClassDefFoundError em repaint de styled labels** — o JIDE (`BasicStyledLabelUI.paintStyledText`) referencia `com.sun.java.swing.plaf.windows.WindowsLookAndFeel`, classe que só existe no JDK Windows. Adicionado shim stub ao `jide-common.jar` (nunca instalado como LAF, só resolve a referência de classe). Fonte em `extras/shim-src/`.
- README atualizado: instalação simplificada no Debian 13, funcionalidades validadas em produção, limitação de "NE Managers simultâneas" removida (era sintoma dos bugs JPMS corrigidos na v1.1).

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

Os fixes JPMS da v1.1 também eliminaram o antigo "limite de NE Managers simultâneas" — era sintoma dos mesmos erros de reflexão que matavam dialogs no EDT, não uma limitação real do app.

### v1.0 (2026-06-01)

Lançamento inicial: 8 patches bsdiff cobrindo SecurityManager, ICE, Freeze/fcache, WindowsComboBoxUI e métodos `exit*`/`matchVersion`.

---

## Notas

A engenharia reversa dos patches, análise de bytecode, investigação das incompatibilidades com Java 21 e desenvolvimento do instalador foram feitos com o auxílio do [Claude Code](https://claude.ai/code) (Anthropic).
