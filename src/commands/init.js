// init.js — the only command for v1
import { existsSync, readdirSync } from 'fs';
import { resolve } from 'path';
import { getTemplate } from '../core/registry.js';
import { collectVariables, previewVariables, confirmProceed, ui } from '../core/prompter.js';
import { renderTemplate } from '../core/renderer.js';
import { findOrphans, removeOrphans } from '../core/cleaner.js';
import { writeFiles, gitInitOrCommit, mvnwValidate } from '../core/writer.js';

const VARIANT_ID = 'compliance-event-logger';

const ALLOWED_PRE_INIT = new Set(['.git', '.gitignore', 'README.md', 'LICENSE']);

export async function initCommand(opts) {
  const outputDir = resolve(opts.output);
  const dryRun = !!opts.dryRun;
  const skipGit = opts.git === false;
  const skipInstall = opts.install === false;

  ui.intro('jsbb init');

  if (!existsSync(outputDir)) {
    ui.outro(`Output directory does not exist: ${outputDir}`);
    process.exit(1);
  }

  const stray = readdirSync(outputDir).filter(e => !ALLOWED_PRE_INIT.has(e));
  if (stray.length > 0) {
    ui.note(stray.slice(0, 10).join(', ') + (stray.length > 10 ? `, ...(${stray.length - 10} more)` : ''),
      'Existing files detected (not a typical "init" baseline)');
    await confirmProceed('Continue anyway? Orphan cleanup will run after generation');
  }

  const template = getTemplate(VARIANT_ID);
  if (!template) {
    ui.outro(`Variant '${VARIANT_ID}' not found in template/`);
    process.exit(1);
  }

  const vars = await collectVariables(template);
  previewVariables(vars);

  await confirmProceed('Proceed with scaffolding?');

  // Render
  const baseDir = resolve(template.path, 'base');
  const files = renderTemplate(baseDir, vars);

  if (dryRun) {
    ui.note(files.map(f => `  ${f.destRelPath}`).join('\n'), `Dry run — ${files.length} files would be written`);
    ui.outro('Dry run complete. No files modified.');
    return;
  }

  // Orphan detection: anything currently on disk that isn't in our expected output
  const expectedPaths = files.map(f => f.destRelPath);
  const orphans = findOrphans(outputDir, expectedPaths);

  if (orphans.length > 0) {
    ui.note(orphans.slice(0, 10).join('\n') + (orphans.length > 10 ? `\n...(${orphans.length - 10} more)` : ''),
      `${orphans.length} orphan file(s) detected (would be removed)`);
    const removeOk = await confirmProceed('Remove orphans?');
    if (removeOk) removeOrphans(outputDir, orphans);
  }

  // Write
  const spin = ui.spinner();
  spin.start('Writing files');
  const written = writeFiles(outputDir, files);
  spin.stop(`Wrote ${written} files`);

  // Git
  if (!skipGit) {
    const git = gitInitOrCommit(outputDir);
    ui.note(git.ok ? `git ${git.existed ? 'commit' : 'init+commit'} completed` : `git skipped: ${git.error}`,
      'git');
  }

  // Maven validate
  if (!skipInstall) {
    spin.start('Running mvnw validate');
    const mvn = mvnwValidate(outputDir);
    if (mvn.ok) {
      spin.stop('mvnw validate succeeded');
    } else if (mvn.skipped) {
      spin.stop(`mvnw skipped: ${mvn.reason}`);
    } else {
      spin.stop(`mvnw validate failed (continuing): ${mvn.error}`);
    }
  }

  ui.outro(`✓ Scaffolded into ${outputDir}`);
}
