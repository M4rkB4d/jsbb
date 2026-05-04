// renderer.js — EJS rendering + path interpolation
// Pattern lifted from forge-cli/src/core/renderer.js
import { readdirSync, readFileSync, statSync } from 'fs';
import { join, relative, sep } from 'path';
import ejs from 'ejs';

const EJS_OPTIONS = {
  strict: false,
  // Use _%> trimming for clean output
};

/**
 * Replace __varName__ placeholders in a path component with vars[varName].
 * E.g., "src/main/java/__packagePath__/Foo.java" → "src/main/java/com/eastwest/afasa/Foo.java"
 */
export function interpolatePath(rawPath, vars) {
  return rawPath.replace(/__([a-zA-Z][a-zA-Z0-9]*)__/g, (_, name) => {
    if (!(name in vars)) {
      throw new Error(`Path placeholder __${name}__ has no matching variable`);
    }
    const value = vars[name];
    // packagePath uses '/'; normalize for cross-platform paths
    return String(value).replace(/\./g, sep === '\\' ? '\\' : '/');
  });
}

/**
 * Recursively walk a base directory, returning [{ srcPath, relPath, isDir }].
 */
function walk(baseDir) {
  const out = [];
  function recurse(currentDir) {
    const entries = readdirSync(currentDir);
    for (const entry of entries) {
      const full = join(currentDir, entry);
      const stat = statSync(full);
      if (stat.isDirectory()) {
        out.push({ srcPath: full, relPath: relative(baseDir, full), isDir: true });
        recurse(full);
      } else {
        out.push({ srcPath: full, relPath: relative(baseDir, full), isDir: false });
      }
    }
  }
  recurse(baseDir);
  return out;
}

/**
 * Render a template directory to a list of { destRelPath, content }.
 * Files ending in .ejs are EJS-rendered with vars; other files are copied as-is.
 * Files that render to empty (after trimming) are skipped — supports conditional inclusion.
 */
export function renderTemplate(baseDir, vars) {
  const items = walk(baseDir);
  const output = [];

  for (const item of items) {
    if (item.isDir) continue; // we'll mkdir for parents on write

    let destRelPath = interpolatePath(item.relPath, vars);
    let content;

    if (destRelPath.endsWith('.ejs')) {
      destRelPath = destRelPath.slice(0, -4); // strip .ejs
      const raw = readFileSync(item.srcPath, 'utf8');
      content = ejs.render(raw, vars, EJS_OPTIONS);
      if (content.trim() === '') continue; // empty render → skip file
    } else {
      content = readFileSync(item.srcPath); // binary-safe Buffer for non-EJS files
    }

    output.push({ destRelPath, content });
  }

  return output;
}
