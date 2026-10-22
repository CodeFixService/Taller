// BiciTaller · Genera los instaladores a partir de schema.sql + cron.sql:
//   supabase/instalar.sql                     (para pegar en el SQL Editor o el instalador corto)
//   supabase/functions/servidor/instalar.ts   (viaja dentro de la función: botón "Actualizar base de datos")
// Uso: node supabase/generar.mjs   (correrlo después de cada cambio en schema.sql o cron.sql)
import { readFileSync, writeFileSync } from 'node:fs';
const dir = new URL('.', import.meta.url);
const schema = readFileSync(new URL('schema.sql', dir), 'utf8'), cron = readFileSync(new URL('cron.sql', dir), 'utf8');
const sql = '-- =====================================================================\n' +
  '--  BiciTaller · INSTALACIÓN / ACTUALIZACIÓN COMPLETA (base de datos + tareas automáticas)\n' +
  '--  Generado de schema.sql + cron.sql. Se puede volver a correr sin perder datos.\n' +
  '-- =====================================================================\n' + schema + cron;
const v = (/function public\.db_version\(\)[\s\S]*?select '([\d.]+)'::text/.exec(schema) || [])[1];
if (!v) throw new Error('No encontré db_version() en schema.sql');
writeFileSync(new URL('instalar.sql', dir), sql);
writeFileSync(new URL('functions/servidor/instalar.ts', dir),
  '// BiciTaller · GENERADO por supabase/generar.mjs (no editar a mano): instalar.sql de la base de datos ' + v + '.\n' +
  'export const DB_VERSION = ' + JSON.stringify(v) + ';\n' +
  'export const INSTALAR = ' + JSON.stringify(sql) + ';\n');
console.log('instalar.sql e instalar.ts listos (base de datos ' + v + ')');
