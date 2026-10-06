# RED DRAGON PARA MACOS

Configurador nativo de macOS para el **Redragon S136: teclado K628 y mouse M693**. Permite leer y guardar ajustes del kit mediante USB HID, con respaldos y verificación de las escrituras.

**Proyecto comunitario independiente, versión preliminar 0.4.0.** Redragon no ha aprobado ni publicado esta aplicación. Las macros están disponibles como función experimental: su almacenamiento y asignación se verificaron, pero su ejecución física sigue pendiente.

[Descargar versión preliminar](https://github.com/martinsantos/red-dragon-para-macos/releases) · [Validación y protocolo](docs/VALIDATION.md) · [Información para Redragon](docs/REDRAGON-ADOPTION.md)

## Funciones

| Función | Alcance comprobado |
|---|---|
| Dibujo interactivo | Teclado de 78 teclas y mouse de siete botones, con selección y función actual |
| Teclas y botones | Reasignación de teclas, modificadores Mac y siete botones del mouse; Fn se conserva |
| RGB | Gráfico del teclado, colores en un clic para todo el teclado o una tecla; azul fijo confirmado en 0.2.1, recorrido gráfico nuevo pendiente de prueba visual |
| DPI | Cinco niveles, con valores 800, 1200, 1600, 2400 o 7200 |
| Polling USB | 125, 250, 500 o 1000 Hz |
| Macros experimentales | Editor de pulsaciones, pausas, repetición y asignación; ejecución pendiente |
| Skin Codex Micro | Seis botones, prefunciones y modo solo indicador; paleta verificada en memoria, prueba visual pendiente |
| Enrutador local | Inicio, fin de tarea y preguntas pendientes del chat conectado; actualización cada segundo |
| Respaldos | JSON antes de aplicar, restauración compatible, lectura posterior y comparación |

Las pruebas de hardware verifican los bytes guardados y restaurados. La lectura de memoria no demuestra por sí sola cada efecto visual, el DPI físico o la ejecución de una macro.

## Usar la app

Requiere **macOS 14 o posterior**. La descarga 0.4.0 incluida es **arm64 para Apple Silicon**, firmada localmente y sin notarización. El código fuente permite compilar para la arquitectura del Mac utilizado.

1. Conectá el receptor USB del kit y encendé el teclado en **2,4 GHz**. Para configurar el mouse en la conexión validada, usá su cable USB.
2. Abrí `RedragonMac.app`.
3. En **Ajustes del Sistema → Privacidad y seguridad → Monitoreo de entrada**, agregá y habilitá la app. Puede aparecer como **RED DRAGON PARA MACOS** o **RedragonMac.app**. En **Respaldo** hay botones para abrir el ajuste y mostrar la app en Finder.
4. Salí con **⌘Q**, volvé a abrirla y pulsá **Detectar**.
5. Seleccioná el periférico. En **Iluminación**, un clic en Azul, Rojo u otro color rápido activa Color fijo y lo guarda directamente. Para otros ajustes, editá y pulsá **Aplicar al dispositivo**. Antes de releer o cambiar de dispositivo, aplicá o descartá los cambios pendientes.

Si aparece `e00002e2` aunque el interruptor esté activado, eliminá la entrada anterior con **−** y agregá de nuevo la app actual con **+**. La recompilación cambia la firma local y el permiso puede seguir asociado al binario anterior. [Permisos de Monitoreo de entrada en macOS](https://support.apple.com/guide/mac-help/mchl4cedafb6/mac).

Los respaldos se guardan en `~/Library/Application Support/RedragonMac/Backups`. **Preparar restauración…** carga un respaldo para revisarlo; **Aplicar al dispositivo** lo escribe. La app intenta recuperar y verificar el respaldo si una escritura falla.

La interfaz de configuración descarta los informes normales de teclas y movimiento. El modo Micro registra únicamente las teclas de acción asignadas del pad; no guarda pulsaciones. El enrutador conserva identificadores y estados derivados de registros locales, sin exportar conversaciones. El conector avanzado opcional permite observar un App Server en localhost.

## Modo Codex Micro

**⌃⌥⌘C — Control + Opción + Comando + C** activa o desactiva las funciones del teclado desde cualquier app mientras RED DRAGON PARA MACOS esté abierta. El menú **Codex**, el botón de la barra superior y los comandos usan la misma operación. Activar elige y lee el K628 aunque esté seleccionado el mouse; desactivar restaura primero el respaldo. Si hay cambios pendientes, deben aplicarse o descartarse. La pantalla muestra «Teclado Micro activo» sólo después de confirmar la escritura.

Desde la carpeta del repositorio:

```sh
./script/codex-mode.sh on       # Activar funciones y luces Micro.
./script/codex-mode.sh off      # Restaurar el teclado anterior.
./script/codex-mode.sh toggle   # Alternar.
./script/codex-mode.sh status   # Consultar el último estado observado por la app.
./script/codex-mode.sh show     # Mostrar la skin sin activar el hardware.
```

El script abre la misma app si hace falta. El CLI incluido en el bundle admite `s136ctl micro on|off|toggle|status|show [--json]` y requiere la app abierta. No crea otro controlador de hardware: envía la orden a la instancia existente por un socket local privado del usuario. Un error de comunicación no confirma el resultado; consultá `status` antes de repetir `toggle`. `on` y `off` son idempotentes.

En el panel o menú Codex, activá **Avisarme cuando Codex necesite respuesta** y permití las notificaciones de macOS. Un nuevo pedido registrado por un chat local conectado produce un aviso con **Activar Codex Micro**. El aviso no cambia el modo automáticamente. Se omiten las preguntas antiguas al abrir o conectar un chat y se evitan avisos duplicados; una pregunta nueva puede avisar aunque otra siga pendiente. La app debe estar abierta y el chat conectado al enrutador local. Las aprobaciones ausentes del registro no generan avisos.

La app usa **una sola ventana**. En la barra superior, el selector **Normal / Codex Micro** cambia de modo dentro de esa ventana. Volver a Normal restaura primero las teclas Micro si están activas. Abrir la app de nuevo enfoca la instancia existente. La skin se puede usar sin modificar el teclado.

- Seis botones corresponden a **Num 1–6**, con el orden físico 4/5/6 arriba y 1/2/3 abajo. Un clic selecciona el botón para configurar su acción; no cambia por sí solo una luz física.
- **Cambiar luces** abre los controles de iluminación dentro de la misma ventana. El bloque de activación del teclado queda arriba. **Micro en pantalla** y **Teclado Micro activo** distinguen la interfaz del control físico.
- Elegí una acción: abrir un chat reciente, abrir el chat local conectado, copiar una prefunción editable o **solo indicador**, sin enviar inputs.
- **Conectar chat local…** enlaza un archivo `rollout-*.jsonl` de `~/.codex/sessions` con el botón seleccionado. Lee el registro cada segundo y conserva solo su identificador, estado y fecha de evento. Los archivos y las rutas quedan en esta Mac.
- Azul indica tarea iniciada, ámbar una pregunta pendiente registrada y verde una tarea terminada. El adaptador muestra el **último estado observado**: no inventa errores, aprobaciones ni actividad que el registro no exponga. Este formato local depende de la versión de Codex y puede requerir adaptación tras una actualización.
- **Activar en teclado** respalda los ajustes antes de asignar las seis teclas y la paleta. **Volver al teclado normal** restaura las seis teclas y las luces. El archivo de recuperación sobrevive al cierre de la app. Si otra app modificó el perfil, hay una recuperación completa con un nuevo respaldo del estado actual.
- Los chats locales y las prefunciones requieren esta app abierta. Las teclas de chat reciente envían `⌘⌥1`…`⌘⌥6` y requieren Codex al frente. Las acciones de app reservan las teclas correspondientes del pad numérico en todos los teclados conectados mientras Micro esté activo.
- La prefunción se copia al portapapeles: pegá con `⌘V` y elegí cuándo enviarla. No se aceptan propuestas automáticamente.
- Los botones en pantalla de chats recientes, dictado y modelo necesitan **Accesibilidad** para enviar sus atajos a Codex. Abrir un chat conectado y copiar una prefunción no requieren ese permiso.

Para enlazar un chat exacto al primer botón al abrir la app:

```sh
open dist/RedragonMac.app --args --micro --follow-codex /ruta/al/rollout-del-chat.jsonl
```

El conector avanzado de App Server es opcional y de solo lectura. Sigue los chats cargados en ese servidor; un servidor nuevo no observa automáticamente las conversaciones de la app de escritorio. [Documentación de Codex App Server](https://learn.chatgpt.com/docs/app-server).

La skin usa la convención visual de [Codex Micro](https://learn.chatgpt.com/docs/features/codex-micro). Es una implementación independiente para Redragon; no agrega la compatibilidad nativa del dispositivo de Work Louder.

## Compatibilidad

| Dispositivo | VID:PID | Conexión |
|---|---|---|
| Receptor del S136 | `320F:50B8` | Teclado en 2,4 GHz validado |
| Mouse M693 | `320F:2225` | USB por cable validado |

El mouse por receptor se detecta, pero aún requiere pruebas. Bluetooth, teclado por cable, otras revisiones, selección de otros perfiles o bancos de colores, DPI arbitrarios, X/Y independientes y efectos dinámicos de audio/pantalla quedan pendientes. La app rechaza estructuras de hardware no reconocidas.

## Compilar y comprobar

Instalá las Command Line Tools de Apple. El paquete usa SwiftPM y no tiene dependencias externas. La compilación local se verificó con Swift 6.2.

```sh
git clone https://github.com/martinsantos/red-dragon-para-macos.git
cd red-dragon-para-macos
./script/check.sh
./script/build_and_run.sh
```

`check.sh` compila la app y el CLI, ejecuta diecisiete comprobaciones del protocolo, los respaldos, el enrutador, los avisos y el canal de comandos, y valida el plist y la firma del bundle. No escribe al hardware. GitHub Actions ejecuta esas comprobaciones en macOS.

```sh
# Generar un ZIP de la compilación release y su SHA-256.
./script/package.sh

# Revisar la interfaz con un respaldo local, sin acceso al kit.
./script/build_and_run.sh --preview /ruta/al/respaldo.json
```

El bundle queda en `dist/RedragonMac.app`; los archivos de compilación, en `work/`. El script también admite `--build-only`, `--verify`, `--debug`, `--logs` y `--telemetry`. `SIGNING_IDENTITY` permite elegir una identidad disponible; la notarización requiere un flujo de distribución adicional.

## Diagnóstico por consola

Después de compilar, el CLI está en `work/build/debug/s136ctl`:

```sh
work/build/debug/s136ctl list
work/build/debug/s136ctl read ID
work/build/debug/s136ctl restore ID RESPALDO.json
work/build/debug/s136ctl codex-state /ruta/al/rollout-del-chat.jsonl
```

Los IDs cambian al reconectar el kit. `verify-roundtrip ID DIRECTORIO` hace cambios temporales, los relee y restaura el estado anterior; `verify-macro` añade una prueba física de 45 segundos. `verify-micro` prueba temporalmente las seis luces y Num 1 durante hasta 45 segundos y restaura los ajustes. Estas pruebas crean un respaldo primero y requieren una conexión estable. El CLI también puede necesitar Monitoreo de entrada para la terminal.

## Estructura

- `RedragonCore`: paquetes HID, transporte, modelo de configuración, macros, lectura/escritura y restauración.
- `RedragonMac`: app SwiftUI; vistas, comandos, estado, repositorio de respaldos e integración AppKit separados.
- `S136CLI`: diagnóstico y pruebas de hardware.
- `ProtocolChecks`: pruebas sin hardware ni XCTest, compatibles con Command Line Tools.

El protocolo de transporte probado se conserva en la refactorización. Se agregó validación de los respaldos importados y protección frente a la pérdida accidental de cambios pendientes. [Cambios](CHANGELOG.md).

## Licencia y adopción

[MIT](LICENSE), copyright 2026 Martín Santos. Redragon y otros desarrolladores pueden usar, modificar y distribuir este código, incluso comercialmente, conservando el aviso de copyright y la licencia. El repositorio no incluye instaladores, binarios ni recursos del software de Windows del fabricante.

**For Redragon engineering:** this is a native macOS S136 configurator offered free of charge under the MIT license. Tested hardware writes and rollback are documented; physical macro execution, additional transports and distribution signing still need validation before official production adoption. See the [engineering handoff](docs/REDRAGON-ADOPTION.md).
