# Contribuir

Usá `./script/check.sh` para compilar y ejecutar las comprobaciones antes de abrir un pull request. El código Swift sigue el formato de `swift format format --in-place --recursive Sources Tests Package.swift`.

Para nuevas revisiones o funciones del hardware, documentá el VID/PID, conexión, capacidades, comandos, campos recuperados y evidencia de lectura. Antes de escribir, guardá un respaldo completo y prepará una restauración verificable. No amplíes los dispositivos que reciben escrituras sólo porque compartan un VID o una familia de protocolo.

Las funciones deben indicar si se comprobó la memoria, la salida física o ambas. No marques la ejecución de macros como validada sólo porque se pudo guardar su tabla.

Mantené los informes normales de teclas y movimiento fuera del flujo de configuración y no adjuntes datos personales, registros de escritura ni instaladores del fabricante a los issues.

Los aportes se publican con la licencia MIT del proyecto.
