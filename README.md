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
│   ├── DotmeshWatchView.mc # la esfera (WatchFace): columna terminal (comentario·prompt·input)
│   └── Palette.mc          # paleta dotmesh (espejo de DESIGN.md)
├── resources/
│   ├── fonts/              # fuentes bitmap generadas (hora, texto, iconos)
│   ├── strings/strings.xml
│   └── drawables/{drawables.xml, launcher_icon.png}
├── scripts/gen-font.py     # regenera una fuente bitmap monoespaciada desde un TTF
├── scripts/gen-iconfont.py # regenera los iconos de la powerline (Nerd Font → PUA)
├── scripts/gen-icon.py     # regenera el launcher icon (mesh de acentos sobre Ink)
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

Dirección **«prompt/terminal»**: la esfera es tu shell. La paleta es la de
[`dotmesh/docs/DESIGN.md`](../dotmesh/docs/DESIGN.md); cualquier cambio de color
empieza allí.

- **Monocromo primero, color = señal.** Fondo negro (AMOLED). Una **columna de
  terminal** alineada a la izquierda, en tres filas: `# sáb 27` como **comentario**
  de código (gris); el **prompt** (*powerline* estilo starship con **borde izquierdo
  recto y pico a la derecha**): **batería** en *peach* · **pasos** en *azul* ·
  **notificaciones** en gris, **violeta** cuando las hay; y debajo, pegada, la hora
  como **input** del terminal: `❯ HH:MM` con chevron *sage*, hora **blanca** y cursor
  `▏` *teal* que parpadea. Los segmentos usan la rampa **chrome** de grafito.
- **Datos reales, sin placeholders.** La powerline muestra lo que el reloj expone:
  batería (con su nivel real, *rose* por debajo del 15 %), pasos y notificaciones.
  Nada se finge.
- **AMOLED / Always-On.** En bajo consumo el fondo es negro puro y todo se
  atenúa: el comentario + `❯ HH:MM` con el cursor fijo, sin powerline. En alta
  potencia `onUpdate` corre cada segundo, así que el cursor parpadea sin
  `onPartialUpdate`.
- **Tipografía.** **JetBrains Mono** bitmap. `scripts/gen-font.py` genera la hora
  (SemiBold ~72 px) y el texto (Medium ~18 px) desde el TTF; los iconos de la
  powerline (batería por niveles, figura andando, campana) los empaqueta
  `scripts/gen-iconfont.py` desde la Nerd Font, remapeados a la PUA del BMP para
  que Connect IQ los resuelva. No se editan los `.fnt`/`.png` a mano.

## Estado

Esfera completa en la dirección «prompt/terminal» v3: columna de terminal a la
izquierda — comentario de fecha, powerline (batería · pasos · notificaciones) y la
hora como input con cursor
vivo. Compila limpio para `epix2pro47mm` y verificada en el simulador CIQ.
Pendiente — verla en el reloj real, cablear las notificaciones al estado del
agente de Claude (ver `bridge/`) y, si se quiere, ajustes o complicaciones.
