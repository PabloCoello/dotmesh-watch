# dotmesh-watch — Guía para agentes

Fuente única de instrucciones para agentes en este repositorio. Claude Code la
lee vía `@AGENTS.md` desde `CLAUDE.md`; OpenCode y Codex la leen directamente.

## Resumen del proyecto

Esfera de reloj **Connect IQ** para **Garmin Epix Pro (Gen 2) 47 mm** y el
**puente (`bridge/`)** para controlar Claude Code desde la muñeca (aprobar/denegar
permisos y reflejar avisos). Es repo **hermano** de [`dotmesh`](../dotmesh), no
parte de su farm de Stow: aquí hay **código de dispositivo** (Monkey C) que se
compila y se sideloadea al reloj, no dotfiles que se enlacen en `$HOME`.

La esfera es la **quinta superficie** del lenguaje visual dotmesh (Paper · Ink ·
Syntax). La paleta es fuente de verdad en
[`dotmesh/docs/DESIGN.md`](../dotmesh/docs/DESIGN.md) y aquí se **consume**, igual
que el tema de VS Code, Warp, Starship y delta.

## Stack

- **Lenguaje**: Monkey C (Connect IQ SDK).
- **Build**: `make` sobre `monkeyc` / `monkeydo` / `connectiq` (simulador).
- **Activos**: fuentes bitmap e icono generados con **Python (Pillow)** desde los
  TTF de JetBrains Mono (incluida la Nerd Font para los iconos de la powerline).
- **Sin tests ni lint.** La verificación es **compilar y mirar en el simulador**
  (o sideload al reloj).

## Comandos

```bash
make key        # genera developer_key.der (una vez; fuera de git)
make build      # compila bin/dotmesh.prg para epix2pro47mm
make sim        # abre el simulador y carga la esfera (monkeydo)
make sideload GARMIN_DIR=/ruta/al/GARMIN   # copia el .prg a un reloj montado
make clean

python3 scripts/gen-font.py <ttf> <px> <charset> <nombre>   # fuente bitmap (hora/texto)
python3 scripts/gen-iconfont.py [px]                        # iconos powerline (Nerd Font → PUA)
python3 scripts/gen-icon.py                                 # regenerar el launcher icon
sudo bash scripts/ubuntu2404-webkit40.sh                    # SDK Manager en Ubuntu 24.04
```

`monkeyc` necesita el Connect IQ SDK en el PATH (lo aporta el SDK Manager). En este
equipo el PATH del SDK aún no es permanente; se exporta leyendo
`~/.Garmin/ConnectIQ/current-sdk.cfg`.

## Arquitectura

- `manifest.xml` — app `watchface`, único device `epix2pro47mm`, GUID, icono.
- `source/` — `DotmeshWatchApp` (entry), `DotmeshWatchView` (la esfera) y
  `Palette.mc` (espejo de la paleta de `DESIGN.md`).
- `resources/fonts/` — fuentes bitmap (`TimeFont`, `SmallFont` por `gen-font.py`;
  `IconFont` por `gen-iconfont.py`) y sus `.fnt`/`.png` **generados**; no a mano.
- `resources/drawables/` — `launcher_icon.png` (generado).
- `bridge/` — plan para aprobar Claude y reflejar avisos desde la muñeca (Tasker +
  approver). Independiente de la esfera. Pendiente.

## Diseño (importante)

El lenguaje visual empieza en `dotmesh/docs/DESIGN.md`. **Si cambias un color, se
cambia allí primero y se propaga aquí.** Principio: monocromo primero, **color solo
como señal**. La esfera es una **columna de terminal** alineada a la izquierda, en
tres filas: `# sáb 27` como **comentario** de código (gris); el **prompt** = powerline
starship con **borde izquierdo recto y pico a la derecha** (rampa **chrome** de
grafito) con 3 segmentos — **batería** (peach) · **pasos** (azul) · **notificaciones**
(gris, **violeta** si las hay); y debajo, pegada, la hora como **input**: chevron `❯`
**sage**, `HH:MM` **blanco** y cursor `▏` **teal** (lo vivo) que parpadea. Señales:
peach = batería, azul = pasos, violeta = notificaciones, rose = batería baja. En AOD:
negro, comentario + `❯ HH:MM` + cursor fijo, sin powerline. Las constantes de layout
viven juntas arriba de `DotmeshWatchView.mc`.

## Límites

**Siempre**
- Compila (`make build`) tras cada cambio; nada se da por bueno sin compilar.
- Regenera fuentes/icono con los scripts; **nunca** edites los `.fnt`/`.png` a mano.
- Toma los colores de `DESIGN.md`.
- Prosa de cara al usuario en **castellano peninsular**.

**Pregunta primero**
- Cambiar la identidad o la disposición visual de la esfera.
- Tocar `manifest.xml` (device, permisos, API level).
- Operaciones Git destructivas o crear repo remoto / push.

**Nunca**
- Commitear `developer_key.*` ni ningún secreto (van en `.gitignore`).
- Atribución de LLM en metadatos de Git (sin `Co-authored-by`, `Generated-by`,
  slugs de rama, etc.) salvo que el usuario lo pida con esa atribución exacta.
- Duplicar skills dentro del proyecto.

## Skills compartidas

Las skills viven en `~/.claude/skills/` (symlink a `~/.agents/skills/`, fuente
canónica en `dotmesh/agents/.agents/skills/`). No las dupliques aquí. El flujo de
skills del core pack es **opt-out**: en cambios no triviales, carga y sigue la skill
de cada fase por iniciativa propia.

## Artefactos de trabajo

- No crees `SPEC.md`, `PLAN.md`, `TODO.md`, `NOTES.md`, `CHECKPOINT.md` en la raíz
  salvo petición explícita.
- Planificación persistente en `.ai/tasks/YYYY-MM-DD-slug/`; scratch en `.ai/tmp/`.
- Solo `.ai/tmp/` está ignorado; versionar `.ai/tasks/` lo decide el proyecto.
