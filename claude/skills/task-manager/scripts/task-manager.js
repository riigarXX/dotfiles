#!/usr/bin/env node

/**
 * Task Manager - Gestión de tareas de desarrollo en Markdown, agrupadas por categoría.
 *
 * Archivos de datos (carpeta `tasks/` en la raíz del repo):
 *   - tasks/tasks.md        → tareas activas (pendiente / en_progreso)
 *   - tasks/tasksDone.md    → tareas finalizadas (archivadas)
 *   - tasks/categories.json → registro de categorías (icono, etiqueta, descripción, orden)
 *
 * La carpeta `tasks/` se crea sola. Si el repo tiene tareas en la ubicación
 * antigua (.claude/tasks.md, .claude/tasksDone.md) se migran automáticamente.
 *
 * Estructura del .md:
 *   [preámbulo libre, editable a mano, se preserva]
 *   <!-- task-manager:start -->   ← todo lo de dentro se REGENERA en cada guardado
 *     leyenda (categorías, columnas, estados)
 *     <!-- cat:<id> --> + "## <icono> <etiqueta>" + descripción + tabla, una por categoría
 *   <!-- task-manager:end -->
 *
 * Formato de fila:
 *   | ID | Título | Descripción | Agente | Nº Agentes | Estado | Bugs | Creada | Actualizada |
 *   La categoría NO es una columna: la da la sección en la que vive la fila.
 *
 * Reglas:
 *   - Estado: pendiente | en_progreso | finalizada (se pinta con icono, se lee sin él)
 *   - Bugs en una celda: "BUG: <desc> → SOL: <sol>" separados por " // "
 *   - "|" dentro de una celda se escapa como "\|"; saltos de línea → espacio
 *   - Si se usa una categoría que no existe, se registra sola en categories.json
 *   - Al finalizar una tarea se MUEVE a tasksDone.md (y al revertirla, vuelve)
 */

import fs from 'fs';
import path from 'path';
import { pathToFileURL } from 'url';
import { randomUUID } from 'crypto';

const REPO_ROOT = path.resolve(process.cwd());
const TASKS_DIR = path.join(REPO_ROOT, 'tasks');
const TASKS_FILE = path.join(TASKS_DIR, 'tasks.md');
const DONE_FILE = path.join(TASKS_DIR, 'tasksDone.md');
const CATEGORIES_FILE = path.join(TASKS_DIR, 'categories.json');

// Ubicación anterior (pre carpeta `tasks/`), solo para migración automática
const LEGACY_TASKS_FILE = path.join(REPO_ROOT, '.claude', 'tasks.md');
const LEGACY_DONE_FILE = path.join(REPO_ROOT, '.claude', 'tasksDone.md');

const VALID_STATUSES = ['pendiente', 'en_progreso', 'finalizada'];

const STATUS_ICONS = {
  pendiente: '🟡',
  en_progreso: '🔵',
  finalizada: '✅'
};

const UNCLASSIFIED = 'sin-clasificar';

// Catálogo por defecto. Si se pide una categoría de aquí, se registra con su
// icono y descripción; si se pide una desconocida, se registra con valores neutros.
const DEFAULT_CATEGORIES = [
  {
    id: 'bug', icon: '🐛', label: 'Bugs',
    description: 'Algo que ya existe y no funciona como debería. Corregir comportamiento incorrecto.',
    aliases: ['bugs', 'fix', 'fixes', 'error', 'errores', 'defecto', 'incidencia']
  },
  {
    id: 'feature', icon: '✨', label: 'Features',
    description: 'Funcionalidad nueva que el producto todavía no tiene.',
    aliases: ['feat', 'features', 'funcionalidad', 'funcionalidades', 'nueva-funcionalidad']
  },
  {
    id: 'mejora', icon: '🚀', label: 'Mejoras',
    description: 'Algo que ya funciona y se pule: usabilidad, rendimiento, ergonomía, robustez.',
    aliases: ['mejoras', 'improvement', 'enhancement', 'optimizacion', 'optimización', 'performance']
  },
  {
    id: 'diseno', icon: '🎨', label: 'Diseño y UI',
    description: 'Estilos, layout, design system, componentes visuales y accesibilidad.',
    aliases: ['diseño', 'design', 'ui', 'ux', 'estilos', 'estilo', 'visual']
  },
  {
    id: 'refactor', icon: '♻️', label: 'Refactor',
    description: 'Reorganización interna sin cambiar el comportamiento observable. Deuda técnica.',
    aliases: ['refactors', 'refactoring', 'limpieza', 'deuda-tecnica', 'deuda']
  },
  {
    id: 'arquitectura', icon: '🏗️', label: 'Arquitectura y fundaciones',
    description: 'Estructura del proyecto, contratos de dominio, módulos base y decisiones estructurales ya tomadas.',
    aliases: ['arquitectura', 'architecture', 'core', 'fundaciones', 'bootstrap', 'setup']
  },
  {
    id: 'seguridad', icon: '🔐', label: 'Seguridad y privacidad',
    description: 'Permisos, datos sensibles, ejecución de código de terceros y políticas de privacidad.',
    aliases: ['security', 'privacidad', 'privacy']
  },
  {
    id: 'test', icon: '🧪', label: 'Tests y QA',
    description: 'Pruebas automáticas, fixtures, verificación y control de calidad.',
    aliases: ['tests', 'testing', 'qa', 'pruebas']
  },
  {
    id: 'docs', icon: '📚', label: 'Documentación',
    description: 'README, guías de uso, documentación técnica y de integración.',
    aliases: ['doc', 'documentacion', 'documentación', 'documentation', 'readme']
  },
  {
    id: 'infra', icon: '🔧', label: 'Infraestructura y build',
    description: 'Build, empaquetado, distribución, CI, dependencias y tooling.',
    aliases: ['build', 'ci', 'tooling', 'devops', 'chore', 'packaging', 'empaquetado']
  },
  {
    id: 'investigacion', icon: '🔍', label: 'Investigación y decisiones',
    description: 'Spikes, comparativas y decisiones pendientes de confirmar antes de implementar.',
    aliases: ['investigación', 'research', 'spike', 'decision', 'decisión', 'decisiones', 'estudio']
  },
  {
    id: UNCLASSIFIED, icon: '📌', label: 'Sin clasificar',
    description: 'Tareas que todavía no tienen categoría. Reclasifícalas con `update <id> category <categoría>`.',
    aliases: ['ninguna', 'otros', 'otro', 'misc']
  }
];

const DEFAULT_PREAMBLE = [
  '# 🗂️ Tareas del repositorio',
  '',
  'Tablero de trabajo de este repositorio, agrupado por tipo de tarea.',
  'Pensado para leerse igual de bien por una persona que por un agente.',
  '',
  '> Gestionado por el script `task-manager.js` (skill **task-manager**).',
  '> Puedes editar libremente **este preámbulo**; todo lo que hay entre las marcas',
  '> `task-manager:start` / `end` se regenera solo en cada operación.',
  ''
].join('\n');

const DEFAULT_DONE_PREAMBLE = [
  '# ✅ Tareas completadas',
  '',
  'Archivo histórico: aquí aterrizan las tareas al pasar a `finalizada`,',
  'conservando su categoría para poder mirar atrás por tipo de trabajo.',
  '',
  '> Gestionado por el script `task-manager.js` (skill **task-manager**).',
  '> Puedes editar libremente **este preámbulo**; el resto se regenera solo.',
  ''
].join('\n');

const GEN_START = '<!-- task-manager:start -->';
const GEN_END = '<!-- task-manager:end -->';

const TABLE_HEADER = '| ID | Título | Descripción | Agente | Nº Agentes | Estado | Bugs | Creada | Actualizada |';
const TABLE_DIVIDER = '| --- | --- | --- | --- | --- | --- | --- | --- | --- |';

/* ------------------------------------------------------------------ *
 * Utilidades de celda
 * ------------------------------------------------------------------ */

function escapeCell(value) {
  return String(value ?? '').replace(/\r?\n/g, ' ').replace(/\|/g, '\\|');
}

function unescapeCell(value) {
  return String(value ?? '').replace(/\\\|/g, '|');
}

function normalizeNumAgents(value) {
  const n = parseInt(String(value ?? '').trim(), 10);
  return Number.isInteger(n) && n >= 1 ? n : 1;
}

function validateNumAgents(value) {
  const raw = String(value ?? '').trim();
  const n = parseInt(raw, 10);
  if (!Number.isInteger(n) || n < 1 || String(n) !== raw) {
    throw new Error(`num_agents debe ser un entero ≥ 1 (recibido: ${value})`);
  }
  return n;
}

// La celda de estado se pinta con icono ("🟡 pendiente"); al leer se queda el valor limpio.
function normalizeStatus(value) {
  const raw = unescapeCell(value).trim();
  const clean = raw.replace(/^[^\p{L}]+/u, '').trim().toLowerCase();
  return VALID_STATUSES.includes(clean) ? clean : clean;
}

// Fecha legible: guardamos y mostramos YYYY-MM-DD (acepta ISO completo de entrada).
function normalizeDate(value) {
  const raw = String(value ?? '').trim();
  const m = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : raw;
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

function bugsToString(bugs) {
  if (!bugs || bugs.length === 0) return '';
  return bugs
    .map(b => {
      const bug = escapeCell(b.bug || '');
      const sol = b.solution && b.solution !== '' ? escapeCell(b.solution) : '(pendiente)';
      return `BUG: ${bug} → SOL: ${sol}`;
    })
    .join(' // ');
}

function bugsFromString(str) {
  const s = String(str ?? '').trim();
  if (!s) return [];
  return s.split(' // ').map(part => {
    let text = part.trim();
    if (text.startsWith('BUG: ')) text = text.slice(5);
    const idx = text.indexOf(' → SOL: ');
    if (idx === -1) return { bug: unescapeCell(text), solution: '' };
    const bug = unescapeCell(text.slice(0, idx));
    let solution = unescapeCell(text.slice(idx + 8));
    if (solution === '(pendiente)') solution = '';
    return { bug, solution };
  });
}

/* ------------------------------------------------------------------ *
 * Categorías
 * ------------------------------------------------------------------ */

function slugifyCategory(value) {
  return String(value ?? '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')  // quita acentos
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || UNCLASSIFIED;
}

function catalogEntry(rawId) {
  const slug = slugifyCategory(rawId);
  return DEFAULT_CATEGORIES.find(c =>
    c.id === slug || (c.aliases || []).some(a => slugifyCategory(a) === slug)
  ) || null;
}

function ensureTasksDir() {
  fs.mkdirSync(TASKS_DIR, { recursive: true });
}

function defaultRegistry() {
  return DEFAULT_CATEGORIES.map(({ id, icon, label, description }, i) => ({
    id, icon, label, description, order: (i + 1) * 10
  }));
}

function loadCategories() {
  ensureTasksDir();
  if (!fs.existsSync(CATEGORIES_FILE)) {
    const registry = defaultRegistry();
    saveCategories(registry);
    return registry;
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(CATEGORIES_FILE, 'utf-8'));
    const list = Array.isArray(parsed) ? parsed : parsed.categories;
    if (!Array.isArray(list) || list.length === 0) return defaultRegistry();
    return list.map((c, i) => ({
      id: slugifyCategory(c.id),
      icon: c.icon || '📌',
      label: c.label || c.id,
      description: c.description || '',
      order: Number.isFinite(c.order) ? c.order : (i + 1) * 10
    }));
  } catch (e) {
    console.error(`[task-manager] categories.json ilegible (${e.message}); se usa el catálogo por defecto.`);
    return defaultRegistry();
  }
}

function saveCategories(categories) {
  ensureTasksDir();
  const sorted = [...categories].sort(byCategoryOrder);
  fs.writeFileSync(CATEGORIES_FILE, `${JSON.stringify({ version: 1, categories: sorted }, null, 2)}\n`);
}

function byCategoryOrder(a, b) {
  if (a.id === UNCLASSIFIED) return 1;
  if (b.id === UNCLASSIFIED) return -1;
  return (a.order ?? 999) - (b.order ?? 999) || a.id.localeCompare(b.id);
}

function findCategory(categories, rawId) {
  const slug = slugifyCategory(rawId);
  const direct = categories.find(c => c.id === slug);
  if (direct) return direct;
  const fromCatalog = catalogEntry(slug);
  return fromCatalog ? categories.find(c => c.id === fromCatalog.id) || null : null;
}

/**
 * Devuelve el id de categoría a usar, registrándola si no existe todavía.
 * Ese es el punto en el que el tablero "aprende" una categoría nueva.
 */
function ensureCategory(rawId, meta = {}) {
  const categories = loadCategories();
  const existing = findCategory(categories, rawId);
  if (existing) {
    let touched = false;
    for (const key of ['icon', 'label', 'description']) {
      if (meta[key] && meta[key] !== existing[key]) { existing[key] = meta[key]; touched = true; }
    }
    if (touched) saveCategories(categories);
    return existing.id;
  }

  const fromCatalog = catalogEntry(rawId);
  const slug = fromCatalog ? fromCatalog.id : slugifyCategory(rawId);
  const label = meta.label || (fromCatalog ? fromCatalog.label : titleCase(slug));
  const entry = {
    id: slug,
    icon: meta.icon || (fromCatalog ? fromCatalog.icon : '📌'),
    label,
    description: meta.description || (fromCatalog ? fromCatalog.description : `Tareas de tipo "${label}".`),
    order: Number.isFinite(meta.order) ? meta.order : nextOrder(categories)
  };
  categories.push(entry);
  saveCategories(categories);
  console.error(`[task-manager] Categoría nueva registrada: ${entry.icon} ${entry.label} (${entry.id})`);
  return entry.id;
}

function nextOrder(categories) {
  const orders = categories.filter(c => c.id !== UNCLASSIFIED).map(c => c.order ?? 0);
  return (orders.length ? Math.max(...orders) : 0) + 10;
}

function titleCase(slug) {
  return String(slug).split('-').filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
}

/* ------------------------------------------------------------------ *
 * Parseo del markdown
 * ------------------------------------------------------------------ */

const CAT_ANCHOR = /^<!--\s*cat:([^\s>]+)\s*-->$/;

function parseRow(line, category) {
  // Divide por "|" sin romper los "\|" escapados dentro de una celda
  const parts = line.split(/(?<!\\)\|/);
  const cells = parts.slice(1, -1).map(c => c.trim());
  const id = unescapeCell(cells[0] || '');
  if (!id) return null;
  if (cells.length >= 9) {
    return {
      id,
      category,
      title: unescapeCell(cells[1] || ''),
      description: unescapeCell(cells[2] || ''),
      agent: unescapeCell(cells[3] || ''),
      num_agents: normalizeNumAgents(cells[4]),
      status: normalizeStatus(cells[5] || ''),
      bugs: bugsFromString(cells[6] || ''),
      created_at: normalizeDate(cells[7] || ''),
      updated_at: normalizeDate(cells[8] || '')
    };
  }
  // Formato antiguo (8 columnas, sin Nº Agentes)
  return {
    id,
    category,
    title: unescapeCell(cells[1] || ''),
    description: unescapeCell(cells[2] || ''),
    agent: unescapeCell(cells[3] || ''),
    num_agents: 1,
    status: normalizeStatus(cells[4] || ''),
    bugs: bugsFromString(cells[5] || ''),
    created_at: normalizeDate(cells[6] || ''),
    updated_at: normalizeDate(cells[7] || ''),
    _legacyRow: true
  };
}

function isTableRow(line) {
  const t = line.trim();
  return t.startsWith('| ') && !t.startsWith('| ID |') && !t.startsWith('| ---');
}

/**
 * Lee las tareas del archivo.
 *  - Formato nuevo: solo se leen las filas que van bajo un ancla `<!-- cat:<id> -->`,
 *    lo que hace imposible que una tabla de la leyenda o del preámbulo cuele como tarea.
 *  - Formato antiguo (sin marcas): se leen todas las filas y caen en "sin-clasificar".
 */
function parseMd(content) {
  const lines = String(content ?? '').split('\n');
  const hasBlock = lines.some(l => l.trim() === GEN_START);
  const tasks = [];
  let needsRewrite = false;

  if (!hasBlock) {
    for (const line of lines) {
      if (!isTableRow(line)) continue;
      const task = parseRow(line, UNCLASSIFIED);
      if (task) tasks.push(task);
    }
    tasks._needsRewrite = tasks.length > 0;
    return tasks;
  }

  let inBlock = false;
  let category = null;
  for (const line of lines) {
    const t = line.trim();
    if (t === GEN_START) { inBlock = true; continue; }
    if (t === GEN_END) { inBlock = false; continue; }
    if (!inBlock) continue;
    const anchor = t.match(CAT_ANCHOR);
    if (anchor) { category = slugifyCategory(anchor[1]); continue; }
    if (category && isTableRow(line)) {
      const task = parseRow(line, category);
      if (task) {
        if (task._legacyRow) { needsRewrite = true; delete task._legacyRow; }
        tasks.push(task);
      }
    }
  }
  tasks._needsRewrite = needsRewrite;
  return tasks;
}

function extractPreamble(content, fallback) {
  const raw = String(content ?? '');
  const lines = raw.split('\n');
  const startIdx = lines.findIndex(l => l.trim() === GEN_START);
  if (startIdx > 0) return lines.slice(0, startIdx).join('\n');
  if (startIdx === 0) return fallback;
  // Archivo en formato antiguo: el preámbulo es lo anterior a la primera tabla
  const tableIdx = lines.findIndex(l => l.trim().startsWith('| ID |'));
  if (tableIdx > 0) return lines.slice(0, tableIdx).join('\n');
  return fallback;
}

/* ------------------------------------------------------------------ *
 * Renderizado del markdown
 * ------------------------------------------------------------------ */

function taskToRow(task) {
  const status = task.status || 'pendiente';
  const icon = STATUS_ICONS[status] || '⚪';
  return [
    task.id,
    escapeCell(task.title),
    escapeCell(task.description),
    escapeCell(task.agent),
    escapeCell(normalizeNumAgents(task.num_agents)),
    escapeCell(`${icon} ${status}`),
    bugsToString(task.bugs),
    escapeCell(normalizeDate(task.created_at)),
    escapeCell(normalizeDate(task.updated_at))
  ].join(' | ');
}

function statusBreakdown(tasks) {
  const counts = {};
  for (const t of tasks) counts[t.status] = (counts[t.status] || 0) + 1;
  return VALID_STATUSES
    .filter(s => counts[s])
    .map(s => `${STATUS_ICONS[s]} ${counts[s]} ${pluralStatus(s, counts[s])}`)
    .join(' · ');
}

function pluralStatus(status, n) {
  if (status === 'en_progreso') return 'en progreso';
  return n === 1 ? status : `${status}s`;
}

function renderLegend(tasks, categories, kind) {
  const total = tasks.length;
  const used = categories.filter(c => tasks.some(t => t.category === c.id));
  const noun = kind === 'done' ? 'tareas finalizadas' : 'tareas activas';
  const lines = [];

  lines.push('## 📖 Cómo leer este archivo');
  lines.push('');
  lines.push(`Hay **${total} ${noun}** repartidas en **${used.length} ${used.length === 1 ? 'categoría' : 'categorías'}**` +
    (total ? `: ${statusBreakdown(tasks)}.` : '.'));
  lines.push('');
  lines.push('Cada categoría tiene su propia sección con título, descripción y tabla. ' +
    'La categoría de una tarea es la sección en la que vive, no una columna.');
  lines.push('');
  lines.push('### 🗂️ Categorías');
  lines.push('');
  lines.push('| Categoría | Tareas | Qué entra aquí |');
  lines.push('|---|---|---|');
  for (const c of categories) {
    const n = tasks.filter(t => t.category === c.id).length;
    lines.push(`| ${c.icon} **${c.label}** <br>\`${c.id}\` | ${n || '—'} | ${c.description} |`);
  }
  lines.push('');
  lines.push('> ¿Falta una categoría? No la metas a mano: créala usando el tipo nuevo');
  lines.push('> (`create ... --type=<nueva>`) o con `categories add`, y el archivo se reorganiza solo.');
  lines.push('');
  lines.push('### 🧭 Columnas');
  lines.push('');
  lines.push('| Columna | Significado |');
  lines.push('|---|---|');
  lines.push('| **ID** | Identificador único de la tarea (UUID). Es el que se pasa al script. |');
  lines.push('| **Título** | Qué hay que hacer, en una línea. |');
  lines.push('| **Descripción** | Contexto, entregable, criterios de aceptación y dependencias. |');
  lines.push('| **Agente** | Agente responsable de ejecutarla. Vacío = lo decide el orquestador. |');
  lines.push('| **Nº Agentes** | Cuántos agentes se despliegan para la tarea (metadato de planificación). |');
  lines.push('| **Estado** | 🟡 `pendiente` · 🔵 `en_progreso` · ✅ `finalizada`. |');
  lines.push('| **Bugs** | Problemas encontrados durante la tarea: `BUG: … → SOL: …`. |');
  lines.push('| **Creada** / **Actualizada** | Fechas (`YYYY-MM-DD`). |');
  lines.push('');
  if (kind === 'done') {
    lines.push('> Todas las tareas de este archivo están ✅ `finalizada`. Si una vuelve a');
    lines.push('> `pendiente` o `en_progreso`, regresa sola a `tasks.md`.');
  } else {
    lines.push('> Al pasar una tarea a ✅ `finalizada` se archiva sola en `tasksDone.md`.');
  }
  lines.push('');
  return lines.join('\n');
}

function renderCategorySection(category, tasks) {
  const lines = [];
  lines.push(`<!-- cat:${category.id} -->`);
  lines.push(`## ${category.icon} ${category.label}`);
  lines.push('');
  if (category.description) {
    lines.push(`> ${category.description}`);
    lines.push('>');
  }
  lines.push(`> **${tasks.length}** ${tasks.length === 1 ? 'tarea' : 'tareas'}` +
    (statusBreakdown(tasks) ? ` · ${statusBreakdown(tasks)}` : ''));
  lines.push('');
  lines.push(TABLE_HEADER);
  lines.push(TABLE_DIVIDER);
  for (const t of tasks) lines.push(`| ${taskToRow(t)} |`);
  lines.push('');
  return lines.join('\n');
}

function serializeMd(tasks, preamble, kind = 'active') {
  const categories = loadCategories();
  // Cualquier categoría presente en las tareas pero no registrada se registra al vuelo
  const known = new Set(categories.map(c => c.id));
  const missing = [...new Set(tasks.map(t => t.category || UNCLASSIFIED))].filter(id => !known.has(id));
  if (missing.length) {
    for (const id of missing) ensureCategory(id);
    return serializeMd(tasks, preamble, kind);
  }

  const sorted = [...categories].sort(byCategoryOrder);
  const sections = [];
  for (const category of sorted) {
    const own = tasks.filter(t => (t.category || UNCLASSIFIED) === category.id);
    if (own.length === 0) continue;   // no ensuciamos el archivo con tablas vacías
    sections.push(renderCategorySection(category, own));
  }
  if (sections.length === 0) {
    sections.push('_Todavía no hay tareas. Crea la primera con `create "Título" "Descripción" --type=<categoría>`._\n');
  }

  const block = [
    GEN_START,
    '<!-- Bloque generado por task-manager.js: se reescribe entero en cada operación. -->',
    '<!-- Edita el preámbulo de arriba libremente; aquí dentro, usa el script. -->',
    '',
    renderLegend(tasks, sorted, kind),
    '---',
    '',
    sections.join('\n'),
    GEN_END
  ].join('\n');

  return `${preamble.trimEnd()}\n\n${block}\n`;
}

/* ------------------------------------------------------------------ *
 * Archivos
 * ------------------------------------------------------------------ */

// Mueve el archivo de la ubicación antigua (.claude/) a `tasks/` si aún vive allí
function migrateLegacyFile(legacyFile, targetFile) {
  if (fs.existsSync(targetFile) || !fs.existsSync(legacyFile)) return false;
  ensureTasksDir();
  fs.renameSync(legacyFile, targetFile);
  console.error(`[task-manager] Migrado ${path.relative(REPO_ROOT, legacyFile)} → ${path.relative(REPO_ROOT, targetFile)}`);
  return true;
}

function ensureFile(file, legacyFile, preamble, kind) {
  ensureTasksDir();
  migrateLegacyFile(legacyFile, file);
  if (!fs.existsSync(file)) {
    fs.writeFileSync(file, serializeMd([], preamble, kind));
  }
}

function ensureTasksFile() {
  ensureFile(TASKS_FILE, LEGACY_TASKS_FILE, DEFAULT_PREAMBLE, 'active');
}

function ensureDoneFile() {
  ensureFile(DONE_FILE, LEGACY_DONE_FILE, DEFAULT_DONE_PREAMBLE, 'done');
}

function loadTasks() {
  ensureTasksFile();
  const content = fs.readFileSync(TASKS_FILE, 'utf-8');
  const tasks = parseMd(content);
  const finalizadas = tasks.filter(t => t.status === 'finalizada');
  if (finalizadas.length > 0) {
    // Migración automática: cualquier finalizada que quede en tasks.md pasa a tasksDone.md
    const activas = tasks.filter(t => t.status !== 'finalizada');
    saveTasks(activas);
    const doneTasks = loadDoneTasks();
    const seen = new Set(doneTasks.map(t => t.id));
    for (const t of finalizadas) {
      if (!seen.has(t.id)) doneTasks.push(t);
    }
    saveDoneTasks(doneTasks);
    return activas;
  }
  if (tasks._needsRewrite) {
    // Migración de formato: archivo antiguo (sin secciones) → estructura por categorías
    console.error(`[task-manager] ${path.relative(REPO_ROOT, TASKS_FILE)} migrado al formato por categorías (${tasks.length} tareas en "${UNCLASSIFIED}").`);
    saveTasks(tasks);
  }
  return tasks;
}

function loadDoneTasks() {
  ensureDoneFile();
  const content = fs.readFileSync(DONE_FILE, 'utf-8');
  const tasks = parseMd(content);
  if (tasks._needsRewrite) {
    console.error(`[task-manager] ${path.relative(REPO_ROOT, DONE_FILE)} migrado al formato por categorías (${tasks.length} tareas en "${UNCLASSIFIED}").`);
    saveDoneTasks(tasks);
  }
  return tasks;
}

function saveTasks(tasks) {
  ensureTasksFile();
  const content = fs.readFileSync(TASKS_FILE, 'utf-8');
  fs.writeFileSync(TASKS_FILE, serializeMd(tasks, extractPreamble(content, DEFAULT_PREAMBLE), 'active'));
}

function saveDoneTasks(tasks) {
  ensureDoneFile();
  const content = fs.readFileSync(DONE_FILE, 'utf-8');
  fs.writeFileSync(DONE_FILE, serializeMd(tasks, extractPreamble(content, DEFAULT_DONE_PREAMBLE), 'done'));
}

/* ------------------------------------------------------------------ *
 * API de tareas
 * ------------------------------------------------------------------ */

function createTask(title, description, agent = '', numAgents = 1, category = UNCLASSIFIED, categoryMeta = {}) {
  const tasks = loadTasks();
  const now = today();
  const task = {
    id: randomUUID(),
    category: ensureCategory(category || UNCLASSIFIED, categoryMeta),
    agent: agent || '',
    num_agents: normalizeNumAgents(numAgents),
    title,
    description,
    bugs: [],
    status: 'pendiente',
    created_at: now,
    updated_at: now
  };
  tasks.push(task);
  saveTasks(tasks);
  return task;
}

function listTasks(filterStatus = null, opts = {}) {
  const tasks = opts.done ? loadDoneTasks() : loadTasks();
  let out = tasks;
  if (filterStatus) out = out.filter(t => t.status === filterStatus);
  if (opts.category) {
    const slug = slugifyCategory(opts.category);
    out = out.filter(t => t.category === slug);
  }
  return out;
}

function getTask(id) {
  const task = loadTasks().find(t => t.id === id);
  if (task) return task;
  return loadDoneTasks().find(t => t.id === id);
}

function updateTask(id, updates) {
  const allowed = ['title', 'description', 'agent', 'status', 'num_agents', 'category'];
  const normalized = { ...updates };
  if ('type' in normalized && !('category' in normalized)) {
    normalized.category = normalized.type;
    delete normalized.type;
  }
  if (normalized.status && !VALID_STATUSES.includes(normalized.status)) {
    throw new Error(`Estado inválido: ${normalized.status}. Válidos: ${VALID_STATUSES.join(', ')}`);
  }
  if (normalized.category) normalized.category = ensureCategory(normalized.category);

  const tasks = loadTasks();
  const doneTasks = loadDoneTasks();
  let idx = tasks.findIndex(t => t.id === id);
  let inDone = false;
  if (idx === -1) {
    idx = doneTasks.findIndex(t => t.id === id);
    if (idx === -1) return null;
    inDone = true;
  }
  const list = inDone ? doneTasks : tasks;
  const task = list[idx];
  const prevStatus = task.status;
  for (const key of Object.keys(normalized)) {
    if (allowed.includes(key)) {
      task[key] = key === 'num_agents' ? validateNumAgents(normalized[key]) : normalized[key];
    }
  }
  task.updated_at = today();

  const moveToDone = !inDone && task.status === 'finalizada' && prevStatus !== 'finalizada';
  const moveToActive = inDone && task.status !== 'finalizada' && prevStatus === 'finalizada';

  if (moveToDone) {
    tasks.splice(idx, 1);
    doneTasks.push(task);
    saveTasks(tasks);
    saveDoneTasks(doneTasks);
  } else if (moveToActive) {
    doneTasks.splice(idx, 1);
    tasks.push(task);
    saveTasks(tasks);
    saveDoneTasks(doneTasks);
  } else if (inDone) {
    saveDoneTasks(doneTasks);
  } else {
    saveTasks(tasks);
  }
  return task;
}

function setCategory(id, category, meta = {}) {
  const slug = ensureCategory(category, meta);
  return updateTask(id, { category: slug });
}

function addBug(id, bug, solution) {
  const tasks = loadTasks();
  const doneTasks = loadDoneTasks();
  let idx = tasks.findIndex(t => t.id === id);
  let inDone = false;
  if (idx === -1) {
    idx = doneTasks.findIndex(t => t.id === id);
    if (idx === -1) return null;
    inDone = true;
  }
  const list = inDone ? doneTasks : tasks;
  list[idx].bugs.push({ bug, solution });
  list[idx].updated_at = today();
  if (inDone) saveDoneTasks(doneTasks); else saveTasks(tasks);
  return list[idx];
}

function setStatus(id, status) {
  return updateTask(id, { status });
}

function deleteTask(id) {
  const tasks = loadTasks();
  const doneTasks = loadDoneTasks();
  let idx = tasks.findIndex(t => t.id === id);
  if (idx !== -1) {
    const [removed] = tasks.splice(idx, 1);
    saveTasks(tasks);
    return removed;
  }
  idx = doneTasks.findIndex(t => t.id === id);
  if (idx !== -1) {
    const [removed] = doneTasks.splice(idx, 1);
    saveDoneTasks(doneTasks);
    return removed;
  }
  return null;
}

// Re-renderiza ambos archivos sin tocar los datos (útil tras editar categorías)
function rerender() {
  saveTasks(loadTasks());
  saveDoneTasks(loadDoneTasks());
}

/* ------------------------------------------------------------------ *
 * CLI (solo al ejecutar directamente; importar no tiene side effects)
 * ------------------------------------------------------------------ */

// Resuelve symlinks: la skill global vive en ~/.claude/skills → ~/dotfiles/claude/skills,
// así que argv[1] (symlink) e import.meta.url (ruta real) no coinciden sin realpath.
function isMainModule() {
  if (!process.argv[1]) return false;
  const candidates = [process.argv[1]];
  try { candidates.push(fs.realpathSync(process.argv[1])); } catch { /* ignora */ }
  return candidates.some(p => import.meta.url === pathToFileURL(p).href);
}

function flag(args, ...names) {
  for (const name of names) {
    const found = args.find(a => a.startsWith(`--${name}=`));
    if (found) return found.slice(name.length + 3);
  }
  return undefined;
}

const USAGE = `Uso:
  create "Título" "Descripción" --type=<categoría> [--agent=<agente>] [--agents=<n>]
                                [--icon=<emoji>] [--label=<etiqueta>] [--desc=<descripción de la categoría>]
  list [--status=pendiente|en_progreso|finalizada] [--type=<categoría>] [--done]
  get <id>
  update <id> <key> <value>          keys: title | description | agent | status | num_agents | category
  set_category <id> <categoría> [--icon=<emoji>] [--label=…] [--desc=…]
  add_bug <id> "bug" "solución"
  set_status <id> <estado>
  delete <id>
  categories                          lista las categorías registradas
  categories add <id> [--icon=…] [--label=…] [--desc=…] [--order=<n>]
  categories update <id> <key> <value>   keys: icon | label | description | order
  rerender                            reescribe los .md desde los datos actuales

Categorías: cada tarea vive en una tabla propia según su tipo (bug, feature, mejora, …).
Si usas un --type que no existe todavía, se registra solo con su icono y descripción.`;

const isMain = isMainModule();

if (isMain) {
  const args = process.argv.slice(2);
  const cmd = args[0];
  const categoryMetaFromArgs = () => ({
    icon: flag(args, 'icon'),
    label: flag(args, 'label'),
    description: flag(args, 'desc', 'description')
  });

  switch (cmd) {
  case 'create': {
    const agent = flag(args, 'agent') ?? '';
    const numAgents = flag(args, 'agents') ?? 1;
    const type = flag(args, 'type', 'category');
    const positional = args.filter(a => !a.startsWith('--'));
    const title = positional[1];
    const description = positional[2];
    if (!title || !description) {
      console.error(USAGE);
      process.exit(1);
    }
    if (!type) {
      console.error('[task-manager] Aviso: creada sin --type=, cae en "sin-clasificar". Clasifícala con set_category.');
    }
    const task = createTask(title, description, agent, numAgents, type || UNCLASSIFIED, categoryMetaFromArgs());
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'list': {
    const status = flag(args, 'status') ?? null;
    const category = flag(args, 'type', 'category');
    const done = args.includes('--done');
    if (status && !VALID_STATUSES.includes(status)) {
      console.error(`Estado inválido: ${status}. Válidos: ${VALID_STATUSES.join(', ')}`);
      process.exit(1);
    }
    console.log(JSON.stringify(listTasks(status, { done, category }), null, 2));
    break;
  }
  case 'get': {
    const id = args[1];
    if (!id) { console.error('Uso: get <id>'); process.exit(1); }
    const task = getTask(id);
    if (!task) { console.error('No encontrada'); process.exit(1); }
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'update': {
    const [, id, key, value] = args.filter(a => !a.startsWith('--'));
    if (!id || !key || value === undefined) { console.error('Uso: update <id> <key> <value>'); process.exit(1); }
    const task = updateTask(id, { [key]: value });
    if (!task) { console.error('No encontrada'); process.exit(1); }
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'set_category': {
    const positional = args.filter(a => !a.startsWith('--'));
    const id = positional[1];
    const category = positional[2];
    if (!id || !category) { console.error('Uso: set_category <id> <categoría> [--icon=…] [--label=…] [--desc=…]'); process.exit(1); }
    const task = setCategory(id, category, categoryMetaFromArgs());
    if (!task) { console.error('No encontrada'); process.exit(1); }
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'add_bug': {
    const [, id, bug, solution] = args.filter(a => !a.startsWith('--'));
    if (!id || !bug || !solution) { console.error('Uso: add_bug <id> "bug" "solución"'); process.exit(1); }
    const task = addBug(id, bug, solution);
    if (!task) { console.error('No encontrada'); process.exit(1); }
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'set_status': {
    const [, id, status] = args.filter(a => !a.startsWith('--'));
    if (!id || !status) { console.error('Uso: set_status <id> <estado>'); process.exit(1); }
    const task = setStatus(id, status);
    if (!task) { console.error('No encontrada'); process.exit(1); }
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'delete': {
    const id = args[1];
    if (!id) { console.error('Uso: delete <id>'); process.exit(1); }
    const task = deleteTask(id);
    if (!task) { console.error('No encontrada'); process.exit(1); }
    console.log(JSON.stringify(task, null, 2));
    break;
  }
  case 'categories': {
    const sub = args[1];
    if (!sub || sub === 'list') {
      console.log(JSON.stringify(loadCategories().sort(byCategoryOrder), null, 2));
      break;
    }
    if (sub === 'add') {
      const id = args[2];
      if (!id) { console.error('Uso: categories add <id> [--icon=…] [--label=…] [--desc=…] [--order=<n>]'); process.exit(1); }
      const orderRaw = flag(args, 'order');
      const slug = ensureCategory(id, {
        ...categoryMetaFromArgs(),
        order: orderRaw !== undefined ? Number(orderRaw) : undefined
      });
      rerender();
      console.log(JSON.stringify(loadCategories().find(c => c.id === slug), null, 2));
      break;
    }
    if (sub === 'update') {
      const id = args[2];
      const key = args[3];
      const value = args[4];
      const keys = ['icon', 'label', 'description', 'order'];
      if (!id || !keys.includes(key) || value === undefined) {
        console.error(`Uso: categories update <id> <${keys.join('|')}> <value>`);
        process.exit(1);
      }
      const categories = loadCategories();
      const cat = findCategory(categories, id);
      if (!cat) { console.error(`Categoría no encontrada: ${id}`); process.exit(1); }
      cat[key] = key === 'order' ? Number(value) : value;
      saveCategories(categories);
      rerender();
      console.log(JSON.stringify(cat, null, 2));
      break;
    }
    console.error('Uso: categories [list] | categories add <id> … | categories update <id> <key> <value>');
    process.exit(1);
    break;
  }
  case 'rerender': {
    rerender();
    console.log(JSON.stringify({ ok: true, files: [path.relative(REPO_ROOT, TASKS_FILE), path.relative(REPO_ROOT, DONE_FILE)] }, null, 2));
    break;
  }
  default:
    console.log(USAGE);
  }
}

export {
  createTask,
  listTasks,
  getTask,
  updateTask,
  setCategory,
  addBug,
  setStatus,
  deleteTask,
  loadTasks,
  loadDoneTasks,
  saveTasks,
  saveDoneTasks,
  loadCategories,
  saveCategories,
  ensureCategory,
  rerender,
  VALID_STATUSES,
  DEFAULT_CATEGORIES
};
