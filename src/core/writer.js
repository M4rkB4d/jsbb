// writer.js — file writing + git + maven
import { existsSync, mkdirSync, writeFileSync, chmodSync } from 'fs';
import { dirname, join } from 'path';
import { execSync } from 'child_process';

// Files that need the executable bit set after write (POSIX only — no-op on Windows).
// The Maven wrapper shell script is the canonical case; without 0755 it can't be
// invoked as `./mvnw` on macOS/Linux.
const EXECUTABLE_BASENAMES = new Set(['mvnw', 'gradlew']);

/**
 * Write a list of { destRelPath, content } to outputDir.
 * On POSIX, chmod 0755 any file whose basename matches EXECUTABLE_BASENAMES.
 */
export function writeFiles(outputDir, files) {
  let written = 0;
  for (const { destRelPath, content } of files) {
    const fullPath = join(outputDir, destRelPath);
    const parent = dirname(fullPath);
    if (!existsSync(parent)) mkdirSync(parent, { recursive: true });
    writeFileSync(fullPath, content);

    if (process.platform !== 'win32') {
      const basename = destRelPath.split(/[\\/]/).pop();
      if (EXECUTABLE_BASENAMES.has(basename)) {
        try { chmodSync(fullPath, 0o755); } catch { /* best-effort */ }
      }
    }

    written += 1;
  }
  return written;
}

/**
 * Initialize a fresh git repo with a baseline commit.
 * If a .git already exists, just commit (preserving caller's existing history).
 */
export function gitInitOrCommit(outputDir, { strict = false } = {}) {
  const dotGit = join(outputDir, '.git');
  const exists = existsSync(dotGit);
  try {
    if (!exists) {
      execSync('git init -b main', { cwd: outputDir, stdio: 'pipe' });
    }
    execSync('git add -A', { cwd: outputDir, stdio: 'pipe' });
    // --allow-empty handles the case where there's nothing new to commit
    execSync(
      `git -c user.email=jsbb@local -c user.name=jsbb commit --allow-empty -m "scaffold(jsbb): compliance-event-logger init"`,
      { cwd: outputDir, stdio: 'pipe' }
    );
    return { ok: true, existed: exists };
  } catch (err) {
    if (strict) throw err;
    return { ok: false, error: err.message, existed: exists };
  }
}

/**
 * Run mvnw validate to verify the scaffold compiles its Maven config.
 */
export function mvnwValidate(outputDir, { strict = false, timeoutMs = 90000 } = {}) {
  const wrapper = process.platform === 'win32' ? 'mvnw.cmd' : './mvnw';
  if (!existsSync(join(outputDir, process.platform === 'win32' ? 'mvnw.cmd' : 'mvnw'))) {
    return { ok: false, skipped: true, reason: 'No mvnw wrapper present' };
  }
  try {
    execSync(`${wrapper} -B -q validate`, {
      cwd: outputDir,
      stdio: 'pipe',
      timeout: timeoutMs,
      shell: true
    });
    return { ok: true };
  } catch (err) {
    if (strict) throw err;
    return { ok: false, error: (err.stderr?.toString() || err.message).slice(0, 400) };
  }
}
