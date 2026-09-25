# N6.3.2 — Ajustes UX del Preset de tablero y Diseño de celda

Implementado el 16/09/2026, sobre los catálogos locales existentes.

- **Título:** `BoardPreset.name` conserva su función administrativa. El campo del editor se presenta como «Título por defecto del Board», con helper sobre el futuro fallback a `device.name`. `titleOverride` ahora se conserva al reabrir/duplicar el preset local; vacío se convierte en null. `showTitleDefault` mantiene su comportamiento. La preview identifica el fallback futuro explícitamente, sin usar el nombre administrativo.
- **Hero:** `CellSizeRole.hero` se serializa como nombre semántico y se resuelve a 4 unidades internas (XXL = 3). Se reutilizan `CellLayoutCanvas`, `cellFit` y la escala del Board: no se guardan tamaños en píxeles ni se cambia el comportamiento por métrica.
- **Reedición:** los diseños explícitos del catálogo ofrecen botones «Editar diseño» y «Duplicar diseño». La edición del mismo ID conserva los drafts y la selección del Board. El catálogo se vuelve a consultar al regresar. Un diseño local usado solo en el Board actual no dispara advertencia por autorreferencia. Los diseños seed/globales o referenciados por otro BoardPreset conservan advertencia y alternativa de duplicación; se permite editar el original con la acción explícita existente.
- **Slots:** se seleccionan en el canvas o mediante chips ordinales. «Eliminar slot seleccionado» aparece en las propiedades únicamente para indicadores. Se quita el elemento elegido, se ordenan los indicadores restantes por ordinal y se reasignan índices 0..n-1, conservando IDs, geometría y estilo. Nuevos slots usan IDs libres; se admiten cero slots.
- **Compatibilidad:** no se modifica `indicatorKeys` al reducir los slots. El validador existente muestra `insufficient_indicator_slots` al regresar al Board.
- **Responsive:** los grupos de propiedades, slots, acciones y advertencia se acomodan verticalmente o mediante Wrap en viewport narrow.

Validación final: 970 tests Flutter aprobados, 1 skip preexistente en `test/widget_test.dart`; `dart analyze` sin errores ni warnings (14 infos fuera de los archivos editados); builds web principal y preview correctos. Recorrido real en Chrome mediante CDP, 36 acciones registradas, ocho capturas obligatorias y una adicional del Board a 390 px. El Board narrow informa scale=0.819; cero eventos Runtime.exceptionThrown en el recorrido.

La prueba visual usó «Sala clima estándar»: creación/reedición y slots sobre Temperatura interior 2×2; value+icon hero en dos entradas sucesivas sobre una copia de «Icono y valor 2×1» aplicada a Humedad interior. La simulación de contenido del editor usa Temperatura interior como demo, independientemente de la métrica elegida en el Board.

Sin Firestore, administración real de DeviceMetricCatalog, Tenant/Site/Device ni persistencia remota agregada. Sin deploy ni modificación del TABLERO productivo. Se preservaron los cambios preexistentes del workspace.

Informe y evidencias: `no_git/informes_de_codigo/informe_etapa_n6_3_2_ajustes_ux_diseno_celda.html`.
