#!/usr/bin/env node
/**
 * 构建 WebUI：压缩 HTML/CSS/JS。
 * JS 只做 terser 压缩，保留全局名（QSC/QscApi/QscUi/QscApp），
 * 避免混淆破坏跨文件引用导致手机端点击全失效。
 */
import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync, cpSync } from 'node:fs';
import { join, resolve, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { minify as minifyHtml } from 'html-minifier-terser';
import CleanCSS from 'clean-css';
import { minify as minifyJs } from 'terser';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const srcDir = join(repoRoot, 'module', 'webroot');
const outDir = join(repoRoot, '.build', 'webroot');

const RESERVED = ['QSC', 'QscApi', 'QscUi', 'QscApp', 'QscTheme', 'ksu', 'exec', 'toast'];

function log(msg) {
  console.log(`[build-web] ${msg}`);
}

async function minifyJavaScript(code, filename) {
  const result = await minifyJs(code, {
    module: false,
    compress: {
      passes: 2,
      drop_console: false,
      pure_funcs: []
    },
    mangle: {
      toplevel: false,
      reserved: RESERVED
    },
    format: { comments: false }
  });
  if (!result.code) throw new Error(`terser failed: ${filename}`);
  return result.code;
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
      minifyJS: false,
      keepClosingSlash: true
    });
    writeFileSync(dest, html, 'utf8');
    return;
  }

  if (lower.endsWith('.css')) {
    const raw = readFileSync(src, 'utf8');
    const css = new CleanCSS({
      level: 2,
      // 保留 WebUI X 的远程 @import（由管理器拦截注入莫奈色，不可在构建期内联）
      inline: false
    }).minify(raw);
    if (css.errors.length) throw new Error(css.errors.join('\n'));
    writeFileSync(dest, css.styles, 'utf8');
    return;
  }

  if (lower.endsWith('.js')) {
    const raw = readFileSync(src, 'utf8');
    writeFileSync(dest, await minifyJavaScript(raw, relPath), 'utf8');
    return;
  }

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
