/* Conexión con Supabase. Ambos valores son públicos por diseño:
   la seguridad está en las reglas de la base de datos (supabase/schema.sql). */
window.BT_CONFIG = {
  SUPABASE_URL: 'https://iwvjthcmufirbnotgixi.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3dmp0aGNtdWZpcmJub3RnaXhpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwMDU1MjMsImV4cCI6MjEwNzU4MTUyM30.54Hc89HlUejofX3knvL4nXDNCphsrZeQG7m50jEIlfw',
  VERSION: '2.25',     // versión de la app (súbela en cada cambio y en version.json)
  DB_VERSION: '2.8',  // versión que debe tener la base de datos (supabase/schema.sql → db_version)
  SERVER_VERSION: '1.9' // versión que debe tener la función "servidor" (supabase/functions/servidor/index.ts)
};
