# Handoff — dotmesh-watch (esfera + bridge)

_Fecha: 2026-06-27. Repo: `~/Documentos/GitHub/dotmesh-watch` (hermano de `dotmesh`)._

## Goal

Integrar el Garmin **Epix Pro (Gen 2) 47 mm** con el flujo de gestionar agentes de
Claude Code desde el móvil (remote control). Dos hilos:

1. **Esfera** Connect IQ con el lenguaje visual dotmesh (dirección "Terminal").
2. **`bridge/`** — aprobar/denegar permisos de Claude y reflejar avisos **desde la
   muñeca** (Android: Tasker + approver). Aún sin implementar.

## State

**Hecho y verificado**
- Toolchain Connect IQ montado en este equipo (Ubuntu 24.04):
  - SDK `connectiq-sdk-lin-9.2.0` + device `epix2pro47mm` instalados vía SDK Manager.
  - Java 8 compila sin problema.
  - SDK Manager arranca con `ciq-sdkmanager` (wrapper en `~/.local/bin`); la app
    está en `~/.local/opt/connectiq-sdk-manager`.
- **Esfera compila y corre en el simulador.** Dirección Terminal:
  - fecha como comentario gris (`// sáb 27 jun`, castellano fijo),
  - hora en **JetBrains Mono** bitmap, **peach**, con dos puntos peach,
  - batería en Paper (rose si ≤15%),
  - **campana de notificaciones** (`DeviceSettings.notificationCount`): contorno gris
    si 0, llena **sage** + contador si >0. Glifo Nerd Font (`0xF0F3`/`0xF0A2`).
- **Commit inicial** `8778fb1` en `main` (autor = identidad git del usuario, **sin
  atribución de LLM**). `developer_key.*` y `bin/` ignorados, fuera del repo.
- **`/setup`** ejecutado: `AGENTS.md` + `CLAUDE.md` (stub `@AGENTS.md`) + `.ai/tmp/`
  en `.gitignore`. Skills OK (`~/.claude/skills → ~/.agents/skills`, sin duplicado).

**En vuelo / sin commitear**
- Los ficheros de `/setup` están **sin commitear**: `M .gitignore`, `?? AGENTS.md`,
  `?? CLAUDE.md`. Más este propio handoff (`.ai/tasks/...`, versionable).

**Pendiente / bloqueado**
- `bridge/` sin implementar (solo el plan en `bridge/README.md`).
- No verificado en **reloj real** (solo simulador).
- PATH del SDK **no permanente** (se exporta a mano cada vez).

## Decisions (y por qué)

- **Repo aparte de dotmesh** — es código de dispositivo (Monkey C), no un dotfile;
  el farm de Stow nunca lo enlazaría. dotmesh sigue siendo fuente de la paleta.
- **La esfera es la "quinta superficie"** del lenguaje dotmesh: consume la paleta de
  `../dotmesh/docs/DESIGN.md`. Cambiar un color empieza allí.
- **Dirección "Terminal"** (elegida por el usuario sobre Editor/gutter y Centrado).
- **Color = señal**: peach = hora (identidad), sage = notificaciones, rose = batería
  baja. El usuario pidió hora en peach y **quitar** el arco/segundos (antes teal).
- **Campana = `notificationCount` real** — es justo lo que sube cuando bridge empuja
  un aviso de Claude al móvil. Sin placeholder.
- **Fuentes bitmap propias** generadas desde el TTF (`scripts/gen-font.py`): blancas
  sobre transparente → Connect IQ las tinta con `setColor`. No editar los `.fnt`/`.png`.
- **bridge** se apoyará en un approver de terceros por ntfy/HTTP (p. ej.
  `claude-remote-approver`) en vez del flujo nativo, por el bug conocido
  [anthropics/claude-code#52084](https://github.com/anthropics/claude-code/issues/52084)
  (aprobar desde el móvil a veces no libera el host). Ver `bridge/README.md`.

## Entorno y trampas (clave para el siguiente agente)

- **Compilar/simular**: exporta el SDK al PATH leyendo el cfg, luego `make`:
  ```bash
  export PATH="$PATH:$(cat ~/.Garmin/ConnectIQ/current-sdk.cfg | sed 's:/*$::')/bin"
  make build && make sim          # sim abre el simulador y carga vía monkeydo
  ```
- **Recargar el simulador** con un build nuevo: matar el `monkeydo` viejo y lanzar
  uno fresco. **Trampa**: `pkill -f monkeydo` **se auto-mata** (el patrón aparece en
  su propia línea de comando → exit 144). Usa el patrón con clase de caracteres y
  **no** pongas la palabra literal en el mismo comando:
  ```bash
  pkill -f 'monkey[d]o'           # comando aparte, sin la palabra literal
  # ...luego, en OTRO comando:
  monkeydo bin/dotmesh.prg epix2pro47mm
  ```
- **Ubuntu 24.04**: el SDK Manager necesita `webkit2gtk-4.0` (libsoup2), retirada de
  noble. Provisión: `sudo bash scripts/ubuntu2404-webkit40.sh` (jammy pineado,
  autolimpieza). El atajo symlink 4.0→4.1 **no** vale (choque libsoup2/3).
- **Secretos**: `developer_key.der`/`.pem` son locales y están en `.gitignore`.
  Nunca commitearlos.

## Next steps (concretos)

1. **Commitear lo de `/setup`** (`AGENTS.md`, `CLAUDE.md`, `.gitignore`) — p. ej.
   `chore: wire dotmesh-watch al sistema de agentes`. (Está sin commitear a propósito.)
2. **Sideload al Epix real** y verla en la muñeca:
   `make sideload GARMIN_DIR=/ruta/al/GARMIN` (en Linux suele montar por MTP).
3. **Implementar `bridge/`**: approver en el host (ntfy/HTTP) + Tasker Trigger
   (Connect IQ) en Android para aprobar/denegar; la campana ya refleja avisos sola.
4. **PATH del SDK permanente** en el zsh de dotmesh (módulo `path`) — opcional.
5. **Detalle abierto**: el chevron `❯` (gris, decorativo) sigue puesto; el usuario no
   ha decidido si quitarlo.

## Suggested skills

- **`source-driven-development`** — todo lo de Connect IQ depende del SDK versionado
  (API, formato `.fnt`, `manifest`); apóyate en la doc, no en memoria.
- **`incremental-implementation`** — el `bridge` en slices probados (approver →
  Tasker → glue), como se hizo con la esfera.
- **`spec-driven-development`** o **`grilling`** — para fijar el diseño del `bridge`
  (qué dispara qué, formato del webhook, estados) antes de construir.
- **`security-and-hardening`** — el `bridge` maneja un endpoint que aprueba acciones
  de Claude: tokens, autenticación del webhook, exposición de red.
- **`git-workflow-and-versioning`** (`/super-git`) — para commitear/PR los siguientes
  cambios sin atribución de LLM.
