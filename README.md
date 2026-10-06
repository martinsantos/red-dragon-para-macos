# RED DRAGON PARA MACOS

Configurador nativo de macOS para el **Redragon S136: teclado K628 y mouse M693**. Permite leer y guardar ajustes del kit mediante USB HID, con respaldos y verificación de las escrituras.

**Proyecto comunitario independiente, versión preliminar 0.2.0.** Redragon no ha aprobado ni publicado esta aplicación. Las macros están disponibles como función experimental: su almacenamiento y asignación se verificaron, pero su ejecución física sigue pendiente.

[Descargar versión preliminar](https://github.com/martinsantos/red-dragon-para-macos/releases) · [Validación y protocolo](docs/VALIDATION.md) · [Información para Redragon](docs/REDRAGON-ADOPTION.md)

## Funciones

| Función | Alcance comprobado |
|---|---|
| Dibujo interactivo | Teclado de 78 teclas y mouse de siete botones, con selección y función actual |
| Teclas y botones | Reasignación de teclas, modificadores Mac y siete botones del mouse; Fn se conserva |
| RGB | Efecto, brillo, velocidad y color; primera paleta personalizada por tecla |
| DPI | Cinco niveles, con valores 800, 1200, 1600, 2400 o 7200 |
| Polling USB | 125, 250, 500 o 1000 Hz |
| Macros experimentales | Editor de pulsaciones, pausas, repetición y asignación; ejecución pendiente |
| Respaldos | JSON antes de aplicar, restauración compatible, lectura posterior y comparación |

Las pruebas de hardware verifican los bytes guardados y restaurados. La lectura de memoria no demuestra por sí sola cada efecto visual, el DPI físico o la ejecución de una macro.

## Usar la app

Requiere **macOS 14 o posterior**. La descarga 0.2.0 incluida es **arm64 para Apple Silicon**, firmada localmente y sin notarización. El código fuente permite compilar para la arquitectura del Mac utilizado.

1. Conectá el receptor USB del kit y encendé el teclado en **2,4 GHz**. Para configurar el mouse en la conexión validada, usá su cable USB.
2. Abrí `RedragonMac.app`.
3. En **Ajustes del Sistema → Privacidad y seguridad → Monitoreo de entrada**, agregá y habilitá la app. Puede aparecer como **RED DRAGON PARA MACOS** o **RedragonMac.app**. En **Respaldo** hay botones para abrir el ajuste y mostrar la app en Finder.
4. Salí con **⌘Q**, volvé a abrirla y pulsá **Detectar**.
5. Seleccioná el periférico, editá sus ajustes y pulsá **Aplicar al dispositivo**. Antes de releer o cambiar de dispositivo, aplicá o descartá los cambios pendientes.

Si aparece `e00002e2` aunque el interruptor esté activado, eliminá la entrada anterior con **−** y agregá de nuevo la app actual con **+**. La recompilación cambia la firma local y el permiso puede seguir asociado al binario anterior. [Permisos de Monitoreo de entrada en macOS](https://support.apple.com/guide/mac-help/mchl4cedafb6/mac).

Los respaldos se guardan en `~/Library/Application Support/RedragonMac/Backups`. **Preparar restauración…** carga un respaldo para revisarlo; **Aplicar al dispositivo** lo escribe. La app intenta recuperar y verificar el respaldo si una escritura falla.

La interfaz descarta los informes normales de teclas y movimiento. No contiene servicios de red ni envía la configuración a servidores.

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

`check.sh` compila la app y el CLI, ejecuta diez comprobaciones del protocolo y los respaldos, y valida el plist y la firma del bundle. No escribe al hardware. GitHub Actions ejecuta esas comprobaciones en macOS.

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
```

Los IDs cambian al reconectar el kit. `verify-roundtrip ID DIRECTORIO` hace cambios temporales, los relee y restaura el estado anterior; `verify-macro` añade una prueba física de 45 segundos. Ambos crean un respaldo primero y requieren una conexión estable. El CLI también puede necesitar Monitoreo de entrada para la terminal.

## Estructura

- `RedragonCore`: paquetes HID, transporte, modelo de configuración, macros, lectura/escritura y restauración.
- `RedragonMac`: app SwiftUI; vistas, comandos, estado, repositorio de respaldos e integración AppKit separados.
- `S136CLI`: diagnóstico y pruebas de hardware.
- `ProtocolChecks`: pruebas sin hardware ni XCTest, compatibles con Command Line Tools.

El protocolo de transporte probado se conserva en la refactorización. Se agregó validación de los respaldos importados y protección frente a la pérdida accidental de cambios pendientes. [Cambios](CHANGELOG.md).

## Licencia y adopción

[MIT](LICENSE), copyright 2026 Martín Santos. Redragon y otros desarrolladores pueden usar, modificar y distribuir este código, incluso comercialmente, conservando el aviso de copyright y la licencia. El repositorio no incluye instaladores, binarios ni recursos del software de Windows del fabricante.

**For Redragon engineering:** this is a native macOS S136 configurator offered free of charge under the MIT license. Tested hardware writes and rollback are documented; physical macro execution, additional transports and distribution signing still need validation before official production adoption. See the [engineering handoff](docs/REDRAGON-ADOPTION.md).
