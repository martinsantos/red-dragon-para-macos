# Cambios

## 0.4.1 · volver a Normal durante una escritura

- Las órdenes de modo esperan la escritura en curso y se ejecutan en orden; la sincronización automática de luces se pausa mientras haya órdenes pendientes.
- Un segundo toggle durante la activación pide volver a Normal, aunque el hardware todavía no haya terminado de activarse.
- Los controles de desactivación siguen disponibles durante la escritura y muestran la operación pendiente en la misma ventana.
- El manejador del pad deja pasar los atajos de otros manejadores de Carbon.
- Dieciocho comprobaciones incluyen el caso de activar y volver inmediatamente, con una sola transición ejecutándose a la vez.

## 0.4.0 · atajo, comandos y avisos de Codex

- Atajo global ⌃⌥⌘C y menú Codex para activar o restaurar el teclado.
- Botón explícito de activación en la barra superior; la skin y las funciones físicas mantienen estados distintos.
- Comandos micro on/off/toggle/status/show y script de acceso, dirigidos a la misma instancia por un canal local privado.
- Activación y restauración compartidas entre botones, atajo, avisos y CLI, con lectura del K628 y confirmación de escritura antes de informar éxito.
- Avisos opcionales de nuevas preguntas del chat local, con acción Activar Codex Micro y sin cambios automáticos del teclado.
- Detección de nuevas preguntas incluso cuando otra sigue pendiente; sin replay al arrancar ni duplicados.
- Diecisiete comprobaciones incluyen límites del canal local, comandos desconocidos, permisos del directorio y transiciones de avisos.

## 0.3.2 · acceso claro a las luces

- Control y activación del teclado visibles arriba en modo Micro.
- Cambiar luces abre Iluminación dentro de la misma ventana.
- El estado diferencia Micro en pantalla, acceso bloqueado y teclado Micro activo.
- Se aclara que los botones seleccionan una tecla para configurarla; no aplican RGB al hacer clic.
- Normal abre inicialmente Iluminación.
- Gráfico del teclado con selector Todo el teclado / Una tecla y aplicación directa de colores.
- Al personalizar una tecla desde un efecto global, el resto de teclas visibles conserva su color configurado; se preservan posiciones internas, mapa y macros.
- Quince comprobaciones locales incluyen esta transición de paleta.

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
