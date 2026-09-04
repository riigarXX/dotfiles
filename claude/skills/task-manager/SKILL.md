---
name: task-manager
description: "Gestiona las tareas de desarrollo de un repositorio en tasks/tasks.md y tasks/tasksDone.md, agrupadas por categoría (bug, feature, mejora, …) con tabla, icono y descripción propios. Úsala para crear, listar, consultar, actualizar, clasificar o borrar tareas, cambiar su estado y registrar bugs. Es la herramienta oficial del agente tasker."
---

# Task Manager Skill

Tablero de tareas de un repositorio en Markdown, **agrupado por categoría**: cada tipo de trabajo tiene su propia sección con icono, título, descripción y tabla. El archivo está pensado para leerse igual de bien por una persona que por un agente.

## Ubicación

Carpeta **`tasks/` en la raíz del repositorio** (se crea sola):

- `tasks/tasks.md` — tareas activas (`pendiente` / `en_progreso`)
- `tasks/tasksDone.md` — tareas finalizadas (archivadas)
- `tasks/categories.json` — registro de categorías (id, icono, etiqueta, descripción, orden)

El script resuelve las rutas contra el **directorio de trabajo actual**: ejecútalo siempre con `cwd` = raíz del repo.

### Dónde está el script

- **Global** (cualquier repo): `~/.claude/skills/task-manager/scripts/task-manager.js`
- **Local del repo**, si existe: `.claude/skills/task-manager/scripts/task-manager.js` (gemela en `.opencode/skills/…`)

Prefiere la copia local si existe; si no, la global. Todas deben ser idénticas.

### Migraciones automáticas

- Tareas en la ubicación antigua (`.claude/tasks.md`) → se mueven solas a `tasks/`.
- Archivo en el formato plano antiguo (una sola tabla) → se reescribe en formato por categorías y **todas las tareas caen en `sin-clasificar`**; hay que reclasificarlas con `set_category`.

## Categorías: el corazón de la skill

**Toda tarea nace con una categoría.** Al crearla se pasa `--type=<categoría>`; si se omite, cae en `sin-clasificar` y el script avisa por stderr.

Catálogo por defecto (con alias, así que `--type=fix`, `--type=research` o `--type=diseño` aterrizan donde toca):

| Categoría | id | Qué entra aquí |
|---|---|---|
| 🐛 Bugs | `bug` | Algo que ya existe y no funciona como debería |
| ✨ Features | `feature` | Funcionalidad nueva que el producto no tiene |
| 🚀 Mejoras | `mejora` | Algo que ya funciona y se pule: UX, rendimiento, robustez |
| 🎨 Diseño y UI | `diseno` | Estilos, layout, design system, accesibilidad |
| ♻️ Refactor | `refactor` | Reorganización interna sin cambiar comportamiento |
| 🏗️ Arquitectura y fundaciones | `arquitectura` | Estructura, contratos de dominio, módulos base |
| 🔐 Seguridad y privacidad | `seguridad` | Permisos, datos sensibles, ejecución de código ajeno |
| 🧪 Tests y QA | `test` | Pruebas, fixtures, verificación |
| 📚 Documentación | `docs` | README, guías, documentación técnica |
| 🔧 Infraestructura y build | `infra` | Build, empaquetado, CI, dependencias, tooling |
| 🔍 Investigación y decisiones | `investigacion` | Spikes, comparativas, decisiones pendientes |
| 📌 Sin clasificar | `sin-clasificar` | Aún sin categoría: reclasificar cuanto antes |

### Si no encaja en ninguna, crea la categoría

Es el comportamiento esperado, no una excepción: **decide el tipo tú**. Si la tarea que te llega no encaja en ninguna categoría existente ("añadir cambio de fuente en ajustes" → eso es una *feature*), úsala; y si de verdad no hay ninguna que sirva, **regístrala con icono, etiqueta y descripción** y queda disponible para siempre:

```bash
node $TM create "Traducir la app" "i18n completa" --type=internacionalizacion \
  --icon=🌍 --label="Internacionalización" --desc="Traducciones, locales y formatos regionales."
```

El script registra la categoría en `categories.json`, crea su sección con tabla y leyenda, y lo avisa por stderr. No hace falta tocar el `.md` a mano. Si no pasas `--icon/--label/--desc`, se registra con valores neutros (📌 + etiqueta derivada del id) y conviene completarla después con `categories update`.

## Estructura del archivo

```
[preámbulo libre — editable a mano, se conserva siempre]

<!-- task-manager:start -->      ← todo lo de aquí dentro lo regenera el script
  ## 📖 Cómo leer este archivo   ← leyenda: categorías, columnas, estados
  <!-- cat:bug -->
  ## 🐛 Bugs
  > descripción + recuento
  | tabla |
  <!-- cat:feature -->
  ...
<!-- task-manager:end -->
```

- El **preámbulo** (lo anterior a `task-manager:start`) es tuyo: ahí va el contexto del proyecto. Se conserva íntegro.
- Dentro del bloque generado **no edites nada a mano**: se reescribe entero en cada operación.
- Solo se pintan las categorías **que tienen tareas**; la leyenda las lista todas con su recuento.
- La categoría de una tarea es **la sección en la que vive**, no una columna.

Columnas de la tabla:

```
| ID | Título | Descripción | Agente | Nº Agentes | Estado | Bugs | Creada | Actualizada |
```

- Estado: `pendiente` 🟡 | `en_progreso` 🔵 | `finalizada` ✅ (se pinta con icono, se lee sin él)
- **Agente**: responsable. `--agent=<agente>`; vacío = lo asigna luego el orquestador
- **Nº Agentes**: metadato de planificación (`--agents=<n>`, entero ≥ 1, por defecto 1)
- Bugs: `BUG: <descripción> → SOL: <solución>`, varios separados por ` // `; sin solución → `SOL: (pendiente)`
- Fechas en `YYYY-MM-DD`
- Un `|` dentro de una celda se escapa como `\|`; saltos de línea → espacio

## Acciones disponibles

| Acción | Descripción |
|--------|-------------|
| `create` | Crea una tarea. Usa **siempre** `--type=<categoría>` |
| `list` | Lista activas; `--status=`, `--type=` y `--done` filtran |
| `get` | Obtiene una tarea por ID (busca en ambos archivos) |
| `update` | Actualiza campos: `title`, `description`, `agent`, `status`, `num_agents`, `category` |
| `set_category` | Reclasifica una tarea (y registra la categoría si es nueva) |
| `add_bug` | Añade bug+solución a una tarea |
| `set_status` | Cambia el estado; `finalizada` **mueve** la tarea a `tasksDone.md` |
| `delete` | Elimina una tarea por ID |
| `categories` | Lista, añade (`add`) o edita (`update`) categorías |
| `rerender` | Reescribe los `.md` desde los datos actuales |

## Uso desde línea de comandos

```bash
# Copia local del repo si existe; si no, la global
TM=.claude/skills/task-manager/scripts/task-manager.js

node $TM create "Título" "Descripción" --type=feature --agent=implementador --agents=2
node $TM list
node $TM list --type=bug
node $TM list --status=en_progreso
node $TM list --done
node $TM get <id>
node $TM update <id> description "Nueva descripción"
node $TM set_category <id> mejora
node $TM set_status <id> finalizada
node $TM add_bug <id> "Descripción bug" "Solución"
node $TM delete <id>

node $TM categories
node $TM categories add rendimiento --icon=⚡ --label="Rendimiento" --desc="Latencia, memoria y tiempos de arranque."
node $TM categories update docs icon 📖
node $TM rerender
```

## Uso desde agente (function calling)

Funciones exportadas en `task-manager.js`:
- `createTask(title, description, agent = '', numAgents = 1, category = 'sin-clasificar', categoryMeta = {})`
- `listTasks(filter?, opts?)` — `opts.done`, `opts.category`
- `getTask(id)` · `updateTask(id, updates)` · `setCategory(id, category, meta?)`
- `addBug(id, bug, solution)` · `setStatus(id, status)` · `deleteTask(id)`
- `loadCategories()` / `saveCategories(list)` / `ensureCategory(id, meta?)`
- `loadTasks()` / `loadDoneTasks()` / `saveTasks(t)` / `saveDoneTasks(t)` / `rerender()`

Para crear muchas tareas de golpe, escribe un script Node temporal que importe `createTask` y lo llame en bucle, en vez de lanzar un proceso por tarea; bórralo al terminar.

## Reglas

- **Clasifica siempre.** Ninguna tarea debería quedarse en `sin-clasificar`: decide el tipo al crearla, y si no existe la categoría, créala con icono y descripción.
- No edites las tablas ni el bloque generado a mano si puedes usar el script.
- El preámbulo sí es editable: ahí va la descripción del proyecto.
- Asigna el agente responsable con `--agent=<agente>` y el nº de agentes con `--agents=<n>`; si el orquestador no los ha indicado, déjalos por defecto y anótalo (no los inventes).
- Al pasar a `finalizada`, la tarea se archiva sola en `tasksDone.md` conservando su categoría.
- No crees archivos alternativos (`tasks.json`, `todo.json`, `TODO.md`) salvo petición explícita.

## Agente tasker

El agente dedicado a crear y mantener tareas es **Tasker** (definido en `~/.claude/agents/tasker.md`, y en `.claude/agents/tasker.md` / `.opencode/agent/tasker.md` si el repo tiene copia local). Usa esta skill para todo: crear con `--type=`, `--agent=` y `--agents=`, clasificar, cambiar estados, registrar bugs, borrar y archivar. El tasker decide la **categoría**; el orquestador decide el **agente** y el **nº de agentes**.
