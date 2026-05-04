// registry.js — discover templates from template/ directory
import { readdirSync, readFileSync, existsSync, statSync } from 'fs';
import { join, dirname, resolve } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATES_ROOT = resolve(__dirname, '..', '..', 'template');

export function getTemplates() {
  if (!existsSync(TEMPLATES_ROOT)) return [];
  const entries = readdirSync(TEMPLATES_ROOT);
  const templates = [];
  for (const entry of entries) {
    const dirPath = join(TEMPLATES_ROOT, entry);
    const metaPath = join(dirPath, 'template.json');
    if (!statSync(dirPath).isDirectory()) continue;
    if (!existsSync(metaPath)) continue;
    try {
      const meta = JSON.parse(readFileSync(metaPath, 'utf8'));
      templates.push({
        id: meta.name || entry,
        path: dirPath,
        meta
      });
    } catch (err) {
      // Skip malformed templates rather than crash
      console.warn(`[registry] Skipping ${entry}: ${err.message}`);
    }
  }
  return templates;
}

export function getTemplate(id) {
  return getTemplates().find(t => t.id === id);
}
