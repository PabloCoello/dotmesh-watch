# bridge — aprobar Claude desde la muñeca

Cómo convertir una pulsación en el Garmin en un "sí/no" a un permiso de Claude
Code, sin sacar el móvil. Es **independiente de la esfera**: la esfera puede
mostrar el estado, pero quien actúa es este puente.

## Arquitectura

```
permiso de Claude ──push──▶ móvil ──▶ Garmin (vibra, lo lees)
        ▲                                  │
        │                            pulsas Aprobar/Denegar
   HTTP approve/deny                       │
        │                                  ▼
   approver (host) ◀── HTTP ── Tasker ◀── Tasker Trigger (Connect IQ)
```

## Piezas

1. **Host (tu Linux)** — un *approver* tipo
   [`claude-remote-approver`](https://github.com/yuuichieguchi/claude-remote-approver)
   convierte cada permiso en un push (vía ntfy) **y** en una acción que se
   dispara con una simple llamada HTTP.
2. **Móvil (Android)** — **Tasker** + la app Connect IQ **Tasker Trigger**.
   Mapeas entradas del reloj a nombres de tarea; al pulsar, el reloj avisa al
   móvil y Tasker ejecuta esa tarea.
3. **Tarea de Tasker** — hace el `HTTP Request` de aprobar (o denegar) contra el
   approver. El reloj nunca habla con Claude directamente.

## Por qué el approver de terceros y no el flujo nativo

El control remoto oficial aprueba desde la app, sin webhook documentado que
Tasker pueda disparar; además hay un bug conocido por el que aprobar desde el
móvil a veces no libera el host. El approver por ntfy/HTTP es predecible y es
justo lo que Tasker sabe llamar.

## Estado

Pendiente. Aquí irán los perfiles/tareas de Tasker exportados (`tasker/`) y el
glue del host (`approver/`, o un README apuntando al proyecto upstream).
