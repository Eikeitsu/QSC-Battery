#!/usr/bin/env node
import { execSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const builtWeb = join(repoRoot, '.build', 'webroot');
const publishDir = join(repoRoot, '.build', 'dist-web-publish');
const branch = 'dist-web';

if (!existsSync(builtWeb)) {
  console.error('[publish-web-branch] missing .build/webroot');
  process.exit(1);
}

const repo = process.env.GITHUB_REPOSITORY;
const token = process.env.GITHUB_TOKEN;
if (!repo || !token) {
  console.log('[publish-web-branch] skip push (GITHUB_REPOSITORY/GITHUB_TOKEN not set)');
  process.exit(0);
}

rmSync(publishDir, { recursive: true, force: true });
mkdirSync(publishDir, { recursive: true });
cpSync(builtWeb, publishDir, { recursive: true });
writeFileSync(
  join(publishDir, 'README.md'),
  '# Built WebUI\n\nCI 自动发布：混淆压缩后的 webroot，勿直接修改。\n'
);

const remote = `https://x-access-token:${token}@github.com/${repo}.git`;
execSync('git init', { cwd: publishDir, stdio: 'inherit' });
execSync('git add -A', { cwd: publishDir, stdio: 'inherit' });
execSync(
  'git -c user.email="github-actions[bot]@users.noreply.github.com" -c user.name="github-actions[bot]" commit -m "chore: publish built webroot"',
  { cwd: publishDir, stdio: 'inherit' }
);
execSync(`git branch -M ${branch}`, { cwd: publishDir, stdio: 'inherit' });
execSync(`git remote add origin "${remote}"`, { cwd: publishDir, stdio: 'inherit' });
execSync(`git push -f origin HEAD:${branch}`, { cwd: publishDir, stdio: 'inherit' });
console.log(`[publish-web-branch] pushed ${branch}`);
