# Cambios

## 0.3.1 · una ventana, dos modos

- Una única escena Window reemplaza a WindowGroup; se elimina Nueva ventana.
- Selector Normal / Codex Micro en la misma ventana.
- Launch Services y un bloqueo por proceso previenen instancias duplicadas; al reabrir se enfoca la ventana existente.
- Los scripts de arranque reutilizan la app en lugar de ejecutar open -n.
- Cerrar la ventana principal sale de la app.
- La falta de Monitoreo de entrada se explica dentro de la ventana con un acceso al ajuste, sin abrir un diálogo al arrancar.

## 0.3.0 · skin Codex Micro y enrutador local

- Skin activable con seis botones del pad numérico y regreso al modo normal.
- Enrutador de los registros locales de Codex: inicio, fin y preguntas pendientes del chat exacto, sin otro servidor ni llamadas a modelos.
- Acciones configurables: chat reciente, chat conectado, prefunción editable o solo indicador sin inputs.
- Respaldo persistente antes de activar teclas y luces; restauración selectiva y recuperación completa.
- Paleta de seis colores escrita, releída y restaurada byte por byte; confirmación visual pendiente.
- No se confirmó F13 durante la prueba: las acciones de app usan las teclas normales del pad y Carbon; su recorrido físico completo requiere validación.
- Conector opcional de solo lectura a un Codex App Server local.
- Catorce comprobaciones locales incluyen recuperación, preguntas simultáneas y lectura incremental de registros.

## 0.2.1 · corrección de iluminación

- Se corrige el registro de color independiente de cada efecto del teclado. Cambiar sólo el RGB general dejaba el color efectivo sin actualizar.
- El azul fijo se confirmó visualmente en el K628 real; después se restauró y verificó la configuración previa.
- Se agregan colores rápidos que activan Color fijo y aplican sólo la iluminación en un clic, conservando otros cambios pendientes.
- El selector muestra el color y el estado Multicolor del registro efectivo.
- Los controles avanzados y los colores por tecla se agrupan para simplificar la pantalla.
- Once comprobaciones locales cubren el protocolo, los respaldos, el gráfico físico y la regresión del color por efecto.

## 0.2.0 · versión preliminar

- Se agregaron dibujos interactivos del teclado y mouse, y el teclado visual para elegir colores por tecla.
- Se separaron paquete HID, endpoint, snapshot y errores en tipos y archivos independientes.
- Se dividió la interfaz en navegación, panel de funciones, barra de estado, toolbar y comandos.
- Se extrajeron la persistencia de respaldos y la integración AppKit del estado de la app.
- La importación de respaldos y el modo de vista previa validan capacidades y tamaños antes de usar los buffers.
- La restauración de respaldos antiguos conserva los buffers opcionales actuales y actualiza la identidad de conexión.
- Los cambios pendientes deben aplicarse o descartarse antes de releer o cambiar de dispositivo.
- Se agregaron pruebas de archivos JSON y de rechazo de respaldos incompatibles.
- Se agregaron licencia MIT, documentación para adopción por Redragon, scripts de empaquetado y CI de macOS.
- Se conserva el alcance de validación de hardware de 0.1.0; las macros siguen experimentales.
