# Cambios

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
