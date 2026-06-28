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
- **Varios hooks, un transporte:**
  - `PreToolUse` (Bash/Write/Edit) → aprobar/denegar herramientas peligrosas.
  - `PreToolUse` (AskUserQuestion) → reflejar las preguntas del arnés al reloj y,
    opcionalmente, responderlas desde la muñeca (ver `SETUP.md`).
  - `Stop` → avisar al terminar con el resumen y aceptar un reprompt.
  - `Notification` → reflejar avisos de inactividad/permiso (solo aviso, no responde).
- **Opt-in por sesión:** solo las conversaciones que marques con `/watch on` (hook
  `UserPromptSubmit`) reenvían al reloj; el resto no molesta. Ver `SETUP.md`.
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
│   ├── pretooluse-ask.sh      # hook PreToolUse AskUserQuestion (reflejar/responder)
│   ├── stop-reprompt.sh       # hook Stop (aviso + reprompt al terminar)
│   ├── notification-notify.sh # hook Notification (avisos idle/permiso)
│   ├── userpromptsubmit-watch.sh # hook UserPromptSubmit (/watch + contexto)
│   ├── watch.sh               # toggle de vigilancia por sesión (respaldo de terminal)
│   ├── reprompt.sh            # envoltorio en desuso (delega en watch.sh)
│   ├── test.sh                # test local sin red
│   └── .env.example           # config (copia a .env, fuera de git)
├── watchapp/                  # approver nativo Connect IQ (camino principal del reloj)
└── tasker/                    # alternativa legada vía Tasker (si ya lo usas)
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

## Lado móvil / reloj

Guía paso a paso completa en [`SETUP.md`](SETUP.md). En corto:

- App **ntfy** en el móvil suscrita a los dos topics; el push lleva botones
  **Aprobar/Denegar** que publican `"<id> allow|deny"` en el topic DEC de un toque.
- **Approver nativo** (recomendado, sin apps de pago): la app Connect IQ de
  [`watchapp/`](watchapp/) publica `allow`/`deny` y los reprompts en ntfy
  directamente desde la muñeca con `makeWebRequest`. Sustituye a Tasker.
- **Tasker** (alternativa legada): Connect IQ *Tasker Trigger* + una tarea que
  publica un `allow`/`deny` "pelado" en el topic DEC. Solo si ya usas Tasker.

## Seguridad

- Token y topics se cargan por `.env`, **nunca** al repo.
- El push **no** lleva contenido de ficheros ni variables: `Bash` → comando
  recortado; `Write`/`Edit` → solo la ruta.
- Ante mala config o timeout, el hook devuelve `ask` (decides en el terminal),
  nunca `allow` mudo.
- Endurecimiento futuro: ntfy self-hosted (tras Tailscale), TTL del id, anti-replay.

## Estado

`approver/` con el hook `PreToolUse`, botones de aprobación en el push y test
(verde). Guía de montaje en [`SETUP.md`](SETUP.md). Pendiente: verificar en el
equipo del usuario (que `deny` funciona en bypass), montar Tasker/Garmin y el hook
`Stop` de reprompt. Plan en `.ai/tasks/2026-06-27-bridge/plan.md`.
