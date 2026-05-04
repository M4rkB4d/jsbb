// cleaner.js — orphan detection (no metadata file approach)
// Lifted from forge-cli/src/core/cleaner.js, adapted for jsbb's narrower scope
import { readdirSync, statSync, unlinkSync, rmdirSync, existsSync } from 'fs';
import { join, relative, sep } from 'path';

const PROTECTED_DIRS = new Set([
  '.git', '.idea', '.vscode', 'target', 'node_modules', '.mvn', 'logs', 'tmp', 'build', 'out'
]);

const PROTECTED_FILES = new Set([
  '.env', '.env.local', '.gitignore', 'mvnw', 'mvnw.cmd', '.editorconfig'
]);

/**
 * Walk a project directory, returning all file paths relative to root.
 * Skips PROTECTED_DIRS entirely.
 */
function walkProject(rootDir) {
  const files = [];
  function recurse(currentDir) {
    if (!existsSync(currentDir)) return;
    const entries = readdirSync(currentDir);
    for (const entry of entries) {
      if (PROTECTED_DIRS.has(entry)) continue;
      const full = join(currentDir, entry);
      const stat = statSync(full);
      if (stat.isDirectory()) {
        recurse(full);
      } else {
        files.push(relative(rootDir, full));
      }
    }
  }
  recurse(rootDir);
  return files;
}

/**
 * Identify orphan files: present on disk but not in the template's expected paths.
 * Returns paths relative to rootDir.
 */
export function findOrphans(rootDir, expectedPaths) {
  if (!existsSync(rootDir)) return [];
  const expected = new Set(expectedPaths.map(p => p.split(/[\\/]/).join(sep)));
  const onDisk = walkProject(rootDir);
  return onDisk.filter(p => {
    if (PROTECTED_FILES.has(p)) return false;
    if (PROTECTED_FILES.has(p.split(sep).pop())) return false;
    return !expected.has(p);
  });
}

/**
 * Delete the listed orphans + remove now-empty directories bottom-up.
 */
export function removeOrphans(rootDir, orphans) {
  for (const rel of orphans) {
    const full = join(rootDir, rel);
    if (existsSync(full)) {
      try { unlinkSync(full); } catch { /* ignore */ }
    }
  }
  // Bottom-up empty-directory cleanup
  function cleanupEmpty(dir) {
    if (!existsSync(dir)) return;
    const entries = readdirSync(dir);
    for (const entry of entries) {
      const full = join(dir, entry);
      try {
        if (statSync(full).isDirectory()) cleanupEmpty(full);
      } catch { /* ignore */ }
    }
    if (existsSync(dir) && readdirSync(dir).length === 0 && dir !== rootDir) {
      try { rmdirSync(dir); } catch { /* ignore */ }
    }
  }
  cleanupEmpty(rootDir);
}
