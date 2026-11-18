import { copyFile, mkdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const prototypeRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packageRoot = resolve(prototypeRoot, 'node_modules/simplebar');
const outputRoot = resolve(prototypeRoot, 'vendor/simplebar');

await mkdir(outputRoot, { recursive: true });
await copyFile(resolve(packageRoot, 'dist/simplebar.min.js'), resolve(outputRoot, 'simplebar.min.js'));
await copyFile(resolve(packageRoot, 'LICENSE'), resolve(outputRoot, 'LICENSE'));
const metadata = JSON.parse(await readFile(resolve(packageRoot, 'package.json'), 'utf8'));
console.log(`Copied SimpleBar ${metadata.version} browser bundle and license.`);
