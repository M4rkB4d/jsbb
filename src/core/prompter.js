// prompter.js — interactive prompts + Java variable derivation
import * as p from '@clack/prompts';

/**
 * Validate groupId is reverse-domain notation (e.g., com.eastwest)
 * Catches the Forge bug where 'my service' (with spaces) silently broke things.
 */
function validateGroupId(value) {
  if (!value || !value.trim()) return 'groupId is required';
  if (!/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$/.test(value.trim())) {
    return 'groupId must be reverse-domain (e.g., com.eastwest, com.eastwest.afasa)';
  }
  return undefined;
}

function validateProjectName(value) {
  if (!value || !value.trim()) return 'projectName is required';
  if (!/^[a-z][a-z0-9-]*[a-z0-9]$/.test(value.trim())) {
    return 'projectName must be lowercase kebab-case (e.g., afasa-engine, aml-logger)';
  }
  return undefined;
}

function toPascalCase(s) {
  return s
    .split('-')
    .filter(Boolean)
    .map(w => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join('');
}

/**
 * Collect template variables interactively, then derive Java-specific ones.
 * Pattern lifted from forge-cli/src/core/prompter.js:70-75 with hardening.
 *
 * If `cliOverrides` is provided (from --groupId=... etc. flags), those values
 * are used directly without prompting. Validation still runs.
 */
export async function collectVariables(template, cliOverrides = {}, nonInteractive = false) {
  p.intro(`jsbb — ${template.meta.displayName || template.id}`);

  const vars = {};
  const definitions = template.meta.variables || {};

  for (const [key, def] of Object.entries(definitions)) {
    if (def.source === 'derived') continue; // computed below

    // CLI override takes precedence; validate then use
    if (cliOverrides[key] !== undefined) {
      const validator = key === 'groupId' ? validateGroupId : (key === 'projectName' ? validateProjectName : null);
      if (validator) {
        const err = validator(cliOverrides[key]);
        if (err) {
          p.cancel(`Invalid --${key}: ${err}`);
          process.exit(1);
        }
      }
      vars[key] = cliOverrides[key];
      continue;
    }

    if (nonInteractive) {
      // Use the default; this requires defaults to be set for non-interactive mode
      if (def.default === undefined) {
        p.cancel(`Non-interactive mode but --${key} not supplied and no default set`);
        process.exit(1);
      }
      vars[key] = def.default;
      continue;
    }

    let value;
    if (def.type === 'select') {
      value = await p.select({
        message: def.prompt,
        options: def.choices.map(c => ({ value: c, label: c })),
        initialValue: def.default
      });
    } else {
      value = await p.text({
        message: def.prompt,
        placeholder: def.default || '',
        defaultValue: def.default,
        validate: key === 'groupId' ? validateGroupId : (key === 'projectName' ? validateProjectName : undefined)
      });
    }

    if (p.isCancel(value)) {
      p.cancel('Cancelled by user');
      process.exit(0);
    }
    vars[key] = value;
  }

  // Java variable derivation (lifted + hardened from forge-cli/src/core/prompter.js:70-75)
  if (template.meta.runtime === 'java' && vars.groupId && vars.projectName) {
    const sanitized = vars.projectName.toLowerCase().replace(/[^a-z0-9]/g, '');
    vars.artifactName = sanitized;
    vars.packageName = `${vars.groupId}.${sanitized}`;
    vars.packagePath = vars.packageName.replace(/\./g, '/');
    vars.className = toPascalCase(vars.projectName);
  }

  // Year for licenses, copyrights, etc.
  vars.currentYear = new Date().getFullYear();

  return vars;
}

export function previewVariables(vars) {
  p.note(
    Object.entries(vars).map(([k, v]) => `  ${k}: ${v}`).join('\n'),
    'Resolved variables'
  );
}

export async function confirmProceed(message, autoYes = false) {
  if (autoYes) return true;
  const ok = await p.confirm({ message });
  if (p.isCancel(ok) || !ok) {
    p.cancel('Cancelled');
    process.exit(0);
  }
  return ok;
}

export const ui = p;
