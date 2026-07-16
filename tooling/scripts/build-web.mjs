#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync, cpSync } from 'node:fs';
import { join, resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { minify as minifyHtml } from 'html-minifier-terser';
import CleanCSS from 'clean-css';
import { minify as minifyJs } from 'terser';
import JavaScriptObfuscator from 'javascript-obfuscator';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const srcDir = join(repoRoot, 'module', 'webroot');
const outDir = join(repoRoot, '.build', 'webroot');

const OBFUSCATOR_OPTIONS = {
  compact: true,
  controlFlowFlattening: true,
  controlFlowFlatteningThreshold: 0.6,
  deadCodeInjection: false,
  identifierNamesGenerator: 'hexadecimal',
  renameGlobals: false,
  selfDefending: false,
  stringArray: true,
  stringArrayEncoding: ['base64'],
  stringArrayThreshold: 0.8,
  transformObjectKeys: true,
  unicodeEscapeSequence: false
};

function log(msg) {
  console.log(`[build-web] ${msg}`);
}

async function minifyJavaScript(code, filename) {
  const terserResult = await minifyJs(code, {
    module: false,
    compress: { passes: 2, drop_console: true },
    mangle: { toplevel: true },
    format: { comments: false }
  });
  if (!terserResult.code) throw new Error(`terser failed: ${filename}`);
  return JavaScriptObfuscator.obfuscate(terserResult.code, OBFUSCATOR_OPTIONS).getObfuscatedCode();
}

async function buildFile(relPath) {
  const src = join(srcDir, relPath);
  const dest = join(outDir, relPath);
  mkdirSync(dirname(dest), { recursive: true });
  const lower = relPath.toLowerCase();

  if (lower.endsWith('.html')) {
    const raw = readFileSync(src, 'utf8');
    const html = await minifyHtml(raw, {
      collapseWhitespace: true,
      removeComments: true,
      removeRedundantAttributes: true,
      removeScriptTypeAttributes: true,
      minifyCSS: true,
      minifyJS: true,
      keepClosingSlash: true
    });
    writeFileSync(dest, html, 'utf8');
    return;
  }

  if (lower.endsWith('.css')) {
    const raw = readFileSync(src, 'utf8');
    const css = new CleanCSS({ level: 2 }).minify(raw);
    if (css.errors.length) throw new Error(css.errors.join('\n'));
    writeFileSync(dest, css.styles, 'utf8');
    return;
  }

  if (lower.endsWith('.js')) {
    const raw = readFileSync(src, 'utf8');
    writeFileSync(dest, await minifyJavaScript(raw, relPath), 'utf8');
    return;
  }

  // 图片等二进制资源原样复制
  cpSync(src, dest);
}

function walk(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...walk(full));
    else files.push(relative(srcDir, full).replace(/\\/g, '/'));
  }
  return files;
}

rmSync(outDir, { recursive: true, force: true });
mkdirSync(outDir, { recursive: true });

for (const file of walk(srcDir)) {
  await buildFile(file);
  log(`built ${file}`);
}

log(`output -> ${outDir}`);
