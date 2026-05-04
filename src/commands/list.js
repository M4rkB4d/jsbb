// list.js — show available templates and their metadata
import { getTemplates } from '../core/registry.js';

export function listCommand() {
  const templates = getTemplates();
  if (templates.length === 0) {
    console.log('No templates found.');
    return;
  }
  for (const t of templates) {
    console.log(`\n${t.id}`);
    console.log(`  ${t.meta.displayName || ''}`);
    console.log(`  runtime: ${t.meta.runtime}`);
    console.log(`  variables:`);
    for (const [key, def] of Object.entries(t.meta.variables || {})) {
      const dflt = def.default ? ` (default: ${def.default})` : '';
      const choices = def.choices ? ` [${def.choices.join('|')}]` : '';
      console.log(`    - ${key}: ${def.prompt}${choices}${dflt}`);
    }
  }
}
