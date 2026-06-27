# bridge — aprobar Claude desde la muñeca

Convierte una pulsación en el Garmin en un "sí/no" a un permiso de Claude Code, y
en un reprompt cuando una tarea termina, sin sacar el móvil. Es **independiente de
la esfera**: la esfera puede mostrar estado, pero quien actúa es este puente.

## Cómo funciona

Sobre el mecanismo **nativo** de Claude Code: los **hooks**. Nada de parchear la
CLI ni de approvers de terceros.

```
Claude (tool-use) ──PreToolUse hook (host)──┐ publica petición + resumen recortado
   ▲                                          ▼
   │ permissionDecision allow/deny      ntfy topic REQ ──push──▶ móvil ──▶ Garmin (vibra)
   │                                                                          │ pulsas
   └──── el hook lee la decisión ◀── ntfy topic DEC ◀── Tasker Trigger ◀──────┘
```

- **Transporte: ntfy ida y vuelta.** El host publica la petición en un topic y
  espera la decisión en otro. Sin puertos abiertos; funciona desde cualquier red.
- **Dos hooks, un transporte:**
  - `PreToolUse` → aprobar/denegar herramientas peligrosas desde la muñeca.
  - `Stop` (pendiente) → avisar al terminar y aceptar un reprompt desde la muñeca.
- **Funciona en bypass.** Los hooks se ejecutan aunque trabajes con permisos en
  bypass (bypass se salta el diálogo, no los hooks), así que solo lo peligroso
  para en el reloj.

## Por qué hooks y no el flujo de terceros

- `permissionPromptTool` está **sin documentar** (sin contrato estable).
- El remote control oficial **no** expone webhook que Tasker pueda disparar.
- `canUseTool` es solo del Agent SDK, no de la CLI interactiva.
- `PreToolUse`/`Stop` tienen contrato documentado y estable. Ver
  [docs de hooks](https://code.claude.com/docs/en/hooks.md).

## Piezas

```
bridge/
├── approver/                  # lado host (este repo)
│   ├── lib.sh                 # transporte ntfy + emisión del JSON del hook
│   ├── pretooluse-approve.sh  # hook PreToolUse (aprobar/denegar)
│   ├── test.sh                # test local sin red
│   └── .env.example           # config (copia a .env, fuera de git)
└── tasker/                    # lado Android (pendiente): perfil Tasker exportado
```

## Puesta en marcha (host)

1. **Config**: `cp approver/.env.example approver/.env` y rellena topics + token.
   Genera topics con `openssl rand -hex 12`. `.env` está en `.gitignore`.
2. **Requisitos**: `curl` y `jq`.
3. **Test**: `bash approver/test.sh` (verde sin necesidad de red ni móvil).
4. **Registra el hook** en `~/.claude/settings.json` (o el `.claude/settings.json`
   del proyecto). Apunta al script por ruta absoluta:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Bash|Write|Edit|MultiEdit|NotebookEdit",
           "hooks": [
             { "type": "command",
               "command": "/ruta/a/dotmesh-watch/bridge/approver/pretooluse-approve.sh",
               "timeout": 300 }
           ]
         }
       ]
     }
   }
   ```

## Lado móvil / reloj (pendiente)

- App **ntfy** en el móvil suscrita a los dos topics; botones de acción para
  aprobar/denegar desde la notificación.
- **Tasker** + Connect IQ **Tasker Trigger**: un botón del Garmin dispara una
  tarea que publica `"<id> allow"` o `"<id> deny"` en el topic de decisiones.

## Seguridad

- Token y topics se cargan por `.env`, **nunca** al repo.
- El push **no** lleva contenido de ficheros ni variables: `Bash` → comando
  recortado; `Write`/`Edit` → solo la ruta.
- Ante mala config o timeout, el hook devuelve `ask` (decides en el terminal),
  nunca `allow` mudo.
- Endurecimiento futuro: ntfy self-hosted (tras Tailscale), TTL del id, anti-replay.

## Estado

`approver/` con el hook `PreToolUse` y su test (verde). Pendiente: verificar en el
equipo del usuario (que `deny` funciona en bypass), cablear Tasker/Garmin y el
hook `Stop` de reprompt. Plan en `.ai/tasks/2026-06-27-bridge/plan.md`.
