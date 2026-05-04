#!/usr/bin/env node
// jsbb — Java Spring Boot Bank CLI
// Single command for v1: `jsbb init`
import { Command } from 'commander';
import { initCommand } from '../src/commands/init.js';
import { listCommand } from '../src/commands/list.js';

const program = new Command();
program
  .name('jsbb')
  .description('Java Spring Boot Bank CLI — scaffolds compliance-event-logger services (AFASA pattern)')
  .version('0.1.0');

program
  .command('init')
  .description('Scaffold a compliance-event-logger Spring Boot project into the current directory')
  .option('-o, --output <dir>', 'Output directory (default: current directory)', process.cwd())
  .option('--dry-run', 'Show what would be generated without writing files', false)
  .option('--no-git', 'Skip git init/commit')
  .option('--no-install', 'Skip mvnw validate after scaffold')
  .option('--non-interactive', 'Use defaults + CLI overrides without prompting (CI-friendly)', false)
  .option('--yes', 'Auto-confirm all prompts (use with --non-interactive)', false)
  .option('--groupId <value>', 'Override prompt: groupId (reverse-domain)')
  .option('--projectName <value>', 'Override prompt: projectName (kebab-case)')
  .option('--javaVersion <value>', 'Override prompt: javaVersion (21|17)')
  .option('--springBootVersion <value>', 'Override prompt: springBootVersion')
  .option('--dbServerName <value>', 'Override prompt: dbServerName')
  .option('--eapiBaseUrl <value>', 'Override prompt: eapiBaseUrl')
  .action(initCommand);

program
  .command('list')
  .description('Show available templates and their metadata')
  .action(listCommand);

program.parse();
