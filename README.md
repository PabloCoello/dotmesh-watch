# dotmesh-watch

Esfera de reloj **dotmesh** para Garmin y el puente para aprobar/denegar
permisos de Claude Code desde la muñeca. Repo hermano de [`dotmesh`](../dotmesh),
no parte de él: aquí hay **código de dispositivo** (Connect IQ / Monkey C) que se
compila y se sideloadea al reloj, no dotfiles que se enlacen en `$HOME` con Stow.

La esfera es la **quinta superficie** del lenguaje visual dotmesh (Paper · Ink ·
Syntax): consume la paleta de [`dotmesh/docs/DESIGN.md`](../dotmesh/docs/DESIGN.md),
igual que el tema de VS Code, el de Warp, Starship y delta. Cualquier cambio de
color empieza allí y se propaga aquí.

## Dos piezas independientes

- **Esfera** (`source/` + `resources/`) — estética pura.
- **`bridge/`** — aprobar/denegar agentes de Claude desde el reloj (Tasker +
  approver). No necesita la esfera para funcionar; ver [`bridge/README.md`](bridge/README.md).

## Dispositivo objetivo

Garmin **Epix Pro (Gen 2) 47 mm** — `epix2pro47mm`, 416×416, redonda, AMOLED.
Para añadir el 42 mm o el 51 mm, suma sus `<iq:product>` en `manifest.xml`.

## Estructura

```
dotmesh-watch/
├── manifest.xml           # app watchface, device epix2pro47mm, GUID, icono
├── monkey.jungle          # config de build
├── source/
│   ├── DotmeshWatchApp.mc  # entry point (AppBase)
│   ├── DotmeshWatchView.mc # la esfera (WatchFace): hora, fecha, segundos, estado
│   └── Palette.mc          # paleta dotmesh (espejo de DESIGN.md)
├── resources/
│   ├── strings/strings.xml
│   └── drawables/{drawables.xml, launcher_icon.png}
├── scripts/gen-icon.py    # regenera el icono (mesh de acentos sobre Ink)
├── bridge/                # aprobar desde la muñeca (pendiente)
└── Makefile
```

## Requisitos

- **Connect IQ SDK** (aporta `monkeyc`, `monkeydo`, `connectiq`) en el PATH.
  Se instala con el SDK Manager de Garmin.
  - *Ubuntu 24.04*: el SDK Manager se enlaza contra **webkit2gtk-4.0** (libsoup2),
    que 24.04 ya no trae. Provisiónalo con `sudo bash scripts/ubuntu2404-webkit40.sh`
    (añade jammy pineado por debajo de noble, instala solo esas libs y retira la
    fuente). El atajo de symlink 4.0→4.1 **no** sirve: mezcla libsoup2 y libsoup3
    en el mismo proceso y el Manager aborta.
- Extensión **Monkey C** de Garmin para VS Code (compila, simula y depura).
- Una **developer key** para firmar; la genera `make key`.

## Uso

```bash
make key      # genera developer_key.der (una vez; queda fuera de git)
make build    # compila bin/dotmesh.prg para epix2pro47mm
make sim      # abre el simulador y carga la esfera
make sideload GARMIN_DIR=/ruta/al/GARMIN   # copia el .prg a un reloj montado
```

En el simulador, elige el device Epix Pro (Gen 2) 47 mm. Para el reloj real,
conéctalo por USB, monta el almacenamiento y apunta `GARMIN_DIR` a la carpeta
`GARMIN` (el target copia a `GARMIN/APPS/`).

## Diseño

- **Monocromo primero**: fondo Ink-0 (`#16171B`), hora en Paper (`#E9EAEC`). El
  color solo como señal — el segundero va en teal (cursor = lo vivo) y el punto
  de estado del agente usará sage/gold/rose.
- **AMOLED / Always-On**: en bajo consumo el fondo pasa a negro puro y los
  segundos se repintan con `onPartialUpdate` recortando una banda mínima, para
  ahorrar batería y no forzar burn-in.
- **Tipografía**: de momento fuentes del sistema. Incrustar **JetBrains Mono**
  (la voz mono de dotmesh) es un follow-up.

## Estado

Andamiaje funcional: una esfera con hora, fecha, segundos y un punto de estado
*placeholder*. Pendiente — cablear ese punto al estado real del agente (ver
`bridge/`), fuentes propias y, si se quiere, complicaciones.
