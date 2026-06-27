# bridge/tasker — perfil de Tasker para decidir desde el reloj

Proyecto de **Tasker** importable que convierte una pulsación en el Garmin en un
POST a tu topic de ntfy: aprobar/denegar un permiso de Claude y reprompt al
terminar. Es el lado **Android** del [bridge](../README.md); el lado host (los
hooks) ya está en [`../approver/`](../approver/).

## Qué trae

`dotmesh-bridge.prj.xml` — un proyecto con seis tareas, cada una un único POST:

| Tarea             | Topic | Cuerpo enviado                          |
|-------------------|-------|-----------------------------------------|
| `bridge_setup`    | —     | fija las variables `%NTFY_BASE/%NTFY_DEC/%NTFY_REP` |
| `bridge_allow`    | DEC   | `allow`                                 |
| `bridge_deny`     | DEC   | `deny`                                  |
| `bridge_continue` | REP   | `continúa con lo siguiente`             |
| `bridge_tests`    | REP   | `ejecuta los tests y arregla lo que falle` |
| `bridge_commit`   | REP   | `haz commit de los cambios`             |

Los cuerpos son **exactamente** los que mandan los botones del push (ver
`approver/lib.sh`), así que el reloj y la notificación disparan lo mismo. La forma
"pelada" (`allow`/`deny`, sin `id`) casa con la única petición pendiente — pensada
para un disparador estático del reloj (ver "Multi-sesión" en [`../SETUP.md`](../SETUP.md)).

## Montaje

### 1. Importar el proyecto

1. Pasa `dotmesh-bridge.prj.xml` al móvil (cualquier carpeta accesible).
2. En Tasker, **long-press en la pestaña de proyectos** (la barra de abajo) →
   **Import** → elige el fichero. Aparece un proyecto `dotmesh-bridge` con las seis
   tareas.

### 2. Pegar tus topics y ejecutar el setup una vez

Tus topics son el **secreto** (ver [`../SETUP.md`](../SETUP.md)); no van en este
repo, por eso el proyecto trae marcadores `REEMPLAZA-…`.

1. Abre la tarea **`bridge_setup`** y, en sus tres acciones *Variable Set*, sustituye:
   - `%NTFY_DEC` → tu `BRIDGE_TOPIC_DEC` (el del `.env` del host).
   - `%NTFY_REP` → tu `BRIDGE_TOPIC_REPROMPT`.
   - `%NTFY_BASE` → déjalo en `https://ntfy.sh` salvo que te autoalojes.
2. **Ejecuta `bridge_setup`** una vez (botón play). Eso fija las variables globales;
   persisten, así que no hay que repetirlo en cada arranque.

> Las demás tareas usan esas variables (`%NTFY_BASE/%NTFY_DEC`, etc.), así que con
> editar solo `bridge_setup` queda todo configurado en un sitio.

### 3. (Opcional) token, si te autoalojas o reservas el topic

En ntfy.sh gratis no hay token (el nombre del topic es el secreto). Si te
autoalojas con auth, abre cada tarea `bridge_*` y, en la acción **HTTP Request**,
campo **Headers**, añade:

```
Authorization:Bearer TU_TOKEN
```

### 4. Disparar desde el Garmin

1. Instala en el reloj la app Connect IQ **Tasker Trigger** (de joaomgcd).
2. Empareja entradas/atajos del reloj con las tareas de Tasker: p. ej. *Aprobar* →
   `bridge_allow`, *Denegar* → `bridge_deny`, y las tres de reprompt según te
   convenga. Los menús exactos varían por versión de la app; la idea es **entrada
   del reloj → tarea de Tasker → POST al topic**.
3. El aviso en la muñeca llega solo: la notificación de ntfy ya se refleja en el
   reloj (vibración + texto).

### 5. Probar

Con el hook del host escuchando (ver [`../SETUP.md`](../SETUP.md), Paso 5),
ejecuta `bridge_allow` a mano desde Tasker: el host debe recibir `allow` en el
topic DEC y liberar el permiso. Igual con `bridge_deny` y las de reprompt.

## Nota sobre el fichero

`dotmesh-bridge.prj.xml` está **escrito a mano** siguiendo el formato de exports
reales de Tasker 6.5 (acción HTTP Request `code 339`, Variable Set `code 547`); no
se ha podido importar en un dispositivo desde aquí. Está bien formado y la
estructura calca un export válido, pero si Tasker se quejara al importar, lo más
rápido es crear una tarea con una sola acción **HTTP Request** (POST,
`%NTFY_BASE/%NTFY_DEC`, cuerpo `allow`) y exportarla para comparar. La fuente del
formato es [Tasker-XML-Info](https://github.com/Taskomater/Tasker-XML-Info).
