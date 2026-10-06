# Protocolo y validación del S136

Validación local: 6 de octubre de 2026, macOS 26, Apple Silicon, Swift 6.2. El acceso se implementó con IOKit/HID en espacio de usuario, sin extensión de kernel.

## Evidencia y método

Se inspeccionó estáticamente el programa de configuración incluido en `Redragon S136_Setup.exe`, descargado previamente por el usuario. El programa de Windows no se ejecutó. Las estructuras recuperadas se contrastaron con lecturas del receptor y del mouse reales, después con escrituras temporales y restauración de los datos originales.

El [paquete oficial del S136](https://redragonshop.com/blogs/product-download/s136-k628-75-mechanical-gaming-keyboard-m693-gaming-mouse-tri-modes-combo) identifica los modelos K628 y M693. También se consultó el [protocolo EVision V2 de OpenRGB](https://github.com/CalcProgrammer1/OpenRGB/tree/master/Controllers/EVisionKeyboardController/EVisionV2KeyboardController) como referencia de familia; sus constantes no se trasladaron directamente porque este kit usa diferencias comprobadas en el ejecutable y el hardware.

## Transporte

Informes HID de salida y entrada de 64 bytes, ID 4. La apertura usa opciones 0 y no toma control exclusivo de las interfaces normales del teclado y mouse.

| Bytes | Significado |
|---|---|
| 0 | ID de informe: 4 |
| 1–2 | Suma little-endian de los bytes 3–63 de la solicitud, antes de colocar la ruta inalámbrica |
| 3 | Comando |
| 4 | Longitud del bloque |
| 5–6 | Desplazamiento little-endian |
| 7 | Estado de respuesta: 0 correcto; otros valores indican rechazo |
| 8… | Datos |
| 32, sólo receptor | Ruta: 1 teclado, 2 mouse |

El receptor transporta hasta 24 bytes por consulta. El mouse directo por USB admite 56 bytes; en ese caso el byte 32 es dato y debe conservarse. La respuesta debe coincidir con la consulta en encabezado, suma, comando, longitud, desplazamiento y ruta cuando corresponda. La suma recibida es el eco de la consulta, no una suma nueva del contenido devuelto.

Cada lectura o escritura se rodea con comandos 1 y 2. Antes del comando 2 se esperan 10 ms, como en el software del fabricante.

## Comandos implementados

| Comando | Función |
|---|---|
| 01 / 02 | Inicio y fin/commit |
| 03 | Capacidades: 34 bytes |
| 05 / 06 | Leer/escribir configuración |
| 08 / 09 | Leer/escribir mapa actual |
| 0A / 0B | Leer/escribir colores personalizados del teclado |
| 14 / 15 | Leer/escribir memoria de macros |

El comando 07 lee el mapa de fábrica, no el mapa editable. Usarlo para comprobar una reasignación da un resultado incorrecto.

## Estructuras comprobadas

Capacidades aceptadas: firma AA55; capacidad de macros 24 × 128 = 3072 bytes. Teclado: valores 6, 128 y tipo 2; mouse: 32, 42 y tipo 1. Una revisión con otra estructura se rechaza.

La configuración tiene 99 bytes por perfil, en bloques de 100 bytes. Se conserva el perfil actual y se escribe el buffer completo en bloques del transporte. Escribir un campo aislado no resultó válido en este kit. Los índices identificados son:

- 1: efecto; 2: brillo; 3: velocidad; 5: multicolor; 6–8: RGB.
- 11: polling USB del mouse, 0/1/2/3 para 125/250/500/1000 Hz.
- 14 + 9 × nivel: registro de DPI. Desplazamientos +2/+3: código del sensor; +4/+5: DPI mostrados. Pares contrastados: 800→6, 1200→16, 1600→26, 2400→46, 7200→96.
- 22 en el teclado: banco de paleta personalizada. La primera paleta usa banco 0 y efecto 19. El stride entre bancos es 512 bytes; esta versión sólo edita el primero.

Cada asignación ocupa 3 bytes. Las teclas usan tipo 20 hex, máscara de modificadores y uso HID; los clics usan tipo 10 hex y máscara de botón. El tipo 71 hex asigna una macro por índice y número de repeticiones. Fn, posición 74 del teclado comprobado, se preserva.

La memoria de macros tiene encabezado de 16 bytes con AA55, longitud y cantidad de macros; sigue una tabla de offsets de 2 bytes. Cada secuencia tiene encabezado de 4 bytes, con cantidad de eventos y dos bytes reservados. Cada evento ocupa 4 bytes: pausa en milisegundos de 16 bits, tipo con bit 80 hex para presionar, y tecla/botón. Se conservan campos reservados y datos no utilizados. El editor exige pulsaciones balanceadas.

El tipo de evento 0 para teclas sigue pendiente de confirmación por ejecución física. El tipo 1 para botones de mouse se encontró en las secuencias del fabricante. Que una tabla se pueda escribir y releer no valida por sí solo su ejecución.

## Resultados

La versión inicial aprobó siete comprobaciones locales: paquete conocido del receptor, suma y offsets, rechazo de respuestas ajenas/antiguas y errores, integridad de campos de DPI, modificadores/Fn, formato y validación de macros, e integridad de colores por tecla.

Pruebas con hardware real:

- Mouse por USB: configuración completa, brillo, mapa de botones, DPI, polling, memoria de macro y asignación; escritura y lectura correctas. Restauración de todos los buffers comparada byte por byte.
- Teclado por receptor 2,4 GHz: configuración completa, brillo, mapa de teclas, memoria de macro, asignación y paleta personalizada; escritura y lectura correctas. Restauración de todos los buffers comparada byte por byte.
- Prueba física de macro F13 con la rueda: el usuario pulsó el botón, pero el monitor no registró F13. Ejecución pendiente de confirmación; datos originales restaurados.
- Aplicación nativa: lectura del teclado confirmada en la interfaz después de renovar el permiso de Monitoreo de entrada. La interfaz mostró K628, perfil 1 y los controles de iluminación con los valores leídos.

Los experimentos produjeron respaldos y salidas locales que se conservaron fuera del repositorio público. El estado visual de las luces, la medición física del sensor/polling y la ejecución de cada asignación no quedan demostrados únicamente por la lectura de memoria.

La aplicación comprueba que los datos no hayan cambiado desde la última lectura antes de aplicar y crea respaldos en disco. Ante un fallo intenta restaurar todos los buffers y vuelve a verificar; si esa comprobación también falla, informa que es necesaria la recuperación con el respaldo.

## Permisos y distribución

La firma es ad hoc y la compilación entregada es arm64. `e00002e2` al abrir HID indica que el proceso no tiene acceso permitido. Se confirmó en el registro TCC que una entrada activada puede corresponder a una firma anterior de esta app; debe quitarse y volver a agregarse la versión actual. No se modificó la base de permisos de macOS ni se desactivaron protecciones del sistema.

## Pendientes

Ejecución física de macros; mouse por receptor; Bluetooth; teclado por USB; otras revisiones; DPI arbitrarios y ajuste X/Y; otros bancos de colores o selección de perfil; efectos dinámicos de audio y pantalla. No se envían comandos de reset, actualización de firmware ni comandos no identificados.

## Refactorización 0.2.0

Se conserva el formato de paquetes, los comandos y el transporte del hardware. Las once comprobaciones locales agregan validación de snapshots importados, compatibilidad de restauración y persistencia JSON. Los cambios de interfaz se revisan en modo de vista previa; no se repiten escrituras al kit como parte del CI. Los dumps de configuración del usuario y los binarios del fabricante no se publican en el repositorio.

## Iluminación corregida en 0.2.1

La prueba visual del usuario mostró que guardar el RGB general no cambiaba la luz del K628. El ejecutable del fabricante actualiza también un registro por efecto: 13 registros de cinco bytes desde el índice 29 de la configuración. Cada registro conserva un byte de selección y contiene Multicolor y RGB. El efecto 6 (Color fijo) usa el registro 4, desplazamiento 49; se actualizan los índices 50–53 junto con los campos generales.

La tabla recuperada de la función 0x4939a0 del programa del fabricante es efecto→registro: 1→0, 2→1, 3→2, 5→3, 6→4, 7→5, 8→6, 9→7, 10→8, 13→9, 14→10, 15→11 y 16→12. Los otros efectos no se fuerzan a una posición de esa tabla.

Se repitió la prueba azul fijo, brillo 100%, Multicolor apagado, con el registro corregido. El usuario confirmó «Sí, ahora quedó azul». La prueba temporal restaura y verifica los buffers anteriores. Esta confirma el color fijo azul del teclado en la conexión comprobada; no valida automáticamente todos los efectos, colores por tecla o conexiones.

Después de abrir la app 0.2.1, el usuario también seleccionó Teclado → Iluminación → Azul y confirmó «Sí, desde la app cambia a azul». Se verificó así el recorrido completo del botón SwiftUI, la escritura y el resultado visible en el K628. La revisión automatizada de otras pantallas se interrumpió por un fallo de SkyComputerUseService; sus gráficos compilaron y la correspondencia de las posiciones del teclado pasó la comprobación local.

## Skin y enrutador local en 0.3.0

- Catorce comprobaciones locales verifican asignaciones de las seis posiciones del pad, conservación de Fn y del resto de la matriz, recuperación selectiva, incompatibilidades y lectura incremental de JSONL, incluso líneas incompletas y truncamiento.
- El registro real del chat de desarrollo devolvió `thinking`, después `attention` con una pregunta pendiente y otra vez `thinking` al recibir la respuesta del usuario. La interfaz mostró el chat conectado y su estado Trabajando. No se publican el registro ni sus rutas.
- Una pregunta pendiente conserva el estado de atención aunque termine el turno; su respuesta permite pasar a completado. Una salida fallida de un comando no se interpreta como error del agente.
- La prueba temporal escribió y releyó Num 1 azul, 2 ámbar, 3 verde, 4 blanco, 5 rojo y 6 apagado. Se restauraron configuración, mapa, macros y paleta originales byte por byte. La confirmación visual del usuario queda pendiente; no se considera verificada.
- El detector no observó F13 durante la primera prueba de inputs. Se sustituyó por usos HID estándar del pad y un registro Carbon de teclas de acción. Su recorrido completo desde una pulsación física hasta la apertura de un chat o copia de prefunción sigue pendiente de confirmación.
- La segunda prueba de uso normal restauró el perfil, pero no hubo una pulsación confirmada dentro de su intervalo. El registro Carbon aceptó Num 1, pero su prueba de callback también terminó sin confirmación física. La ausencia de detección no se considera prueba de funcionamiento.
- El adaptador local depende del formato de eventos observado en esta versión de Codex Desktop. No observa aprobaciones, errores ni actividad ausentes del registro. El conector avanzado de App Server no fue validado contra el servidor privado de la app de escritorio.


## Ventana única en 0.3.1

La revisión de la app mostró un único elemento de ventana principal con ID `main`. El selector Normal / Codex Micro cambió el contenido sin cambiar esa identidad de ventana. Se cerraron las instancias de prueba y anteriores. Launch Services prohíbe nuevas instancias y el bloqueo nativo previene duplicados incluso si se ejecuta directamente el binario. Los scripts usan `open` sin `-n`. El permiso de Monitoreo de entrada sigue siendo requerido para el hardware; el enrutador local y la skin funcionan sin él.

## Controles de iluminación en 0.3.2

El gráfico permite elegir Todo el teclado o Una tecla. Los ocho colores rápidos se guardan directamente con respaldo y lectura posterior. Al pasar de un efecto general a una tecla personalizada, las demás teclas visibles conservan el color configurado del efecto anterior; no se reutiliza una paleta antigua sin mostrarla. Las quince comprobaciones locales y el CI verifican este comportamiento, las posiciones ocultas y la conservación del mapa, las macros y los campos ajenos al cambio.

En esta compilación se confirmó que el permiso activado correspondía a otra firma. Con autorización del usuario se reemplazó la entrada mediante Ajustes del Sistema y se comprobó que el permiso autorizado coincidiera con la firma del bundle actual. Tras reiniciar la misma app, desapareció el bloqueo y la interfaz mostró «Leído · perfil 1 · teclado», con los controles habilitados. No se recompiló ni se volvió a firmar el bundle después de renovar el permiso.

La interfaz del mouse USB mostró un color violeta y «Color fijo guardado y verificado» durante la revisión. Esto acredita la confirmación de escritura de la app, sin sustituir una observación física de la luz. La prueba visual del gráfico nuevo en el teclado sigue pendiente: la herramienta de control de interfaz dejó de responder durante la prueba. El azul fijo confirmado desde la app 0.2.1 continúa documentado por separado.

## Atajo, comandos y avisos en 0.4.0

Diecisiete comprobaciones locales y la compilación release aprobaron. Las pruebas nuevas cubren comandos desconocidos y versiones incompatibles, ausencia del servidor, permisos privados y rechazo de enlaces simbólicos del directorio, lectura acotada de mensajes, omisión del historial de avisos y una pregunta nueva mientras otra sigue pendiente.

Se probó el canal local contra la app real: `micro status` consultó el estado; `micro on` devolvió error y `hardwareActive: false` cuando macOS bloqueaba el acceso, sin crear recuperación. Después de renovar el mismo permiso para la firma final, `micro on` activó el teclado, guardó el respaldo y la interfaz mostró «Teclado Micro activo». `micro off` confirmó la restauración y pasó a Normal. Una lectura independiente comparó configuración, mapa, macros y paleta con el respaldo previo: los cuatro buffers coincidieron byte por byte. `micro show` mostró el panel en la misma ventana manteniendo el hardware desactivado.

El atajo global ⌃⌥⌘C se registró sin error con Carbon. La simulación de teclas de la herramienta de interfaz no disparó el atajo; su confirmación desde el teclado físico sigue pendiente. Las teclas físicas Num 1–6 continúan pendientes de validación independiente.

Se habilitó la preferencia de avisos en la app. La entrega del aviso depende del permiso de Notificaciones de macOS; la herramienta de interfaz se interrumpió al revisar ese permiso, por lo que no se considera comprobada la entrega del banner ni su botón de activación. Los avisos requieren el chat local conectado y la app abierta. No activan el teclado ni resuelven aprobaciones automáticamente.
