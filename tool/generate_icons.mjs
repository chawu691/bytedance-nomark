import {
  copyFile,
  mkdir,
  readFile,
  stat,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const toolDir = path.dirname(fileURLToPath(import.meta.url));
const projectDir = path.dirname(toolDir);
const sourceSvg = path.resolve(projectDir, '..', 'svg.svg');
const source = await readFile(sourceSvg);
const generatedPngs = [];

async function renderPng(relativePath, size) {
  const output = path.join(projectDir, relativePath);
  await mkdir(path.dirname(output), { recursive: true });
  const png = await sharp(source)
    .resize(size, size, { fit: 'contain' })
    .png()
    .toBuffer();
  await writeFile(output, png);
  generatedPngs.push({ output, size });
  return png;
}

const androidIcons = {
  'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
  'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
  'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
  'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
  'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
};

for (const [target, size] of Object.entries(androidIcons)) {
  await renderPng(target, size);
}

async function renderAssetCatalog(relativeContentsPath) {
  const contentsPath = path.join(projectDir, relativeContentsPath);
  const catalog = JSON.parse(await readFile(contentsPath, 'utf8'));
  const directory = path.dirname(relativeContentsPath);
  const rendered = new Map();
  for (const image of catalog.images ?? []) {
    if (!image.filename || !image.size || !image.scale) continue;
    const points = Number.parseFloat(image.size.split('x')[0]);
    const scale = Number.parseFloat(image.scale);
    const pixels = Math.round(points * scale);
    const key = `${image.filename}:${pixels}`;
    if (rendered.has(key)) continue;
    rendered.set(key, true);
    await renderPng(path.join(directory, image.filename), pixels);
  }
}

await renderAssetCatalog(
  'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
);
await renderAssetCatalog(
  'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json',
);

await renderPng('linux/runner/resources/app_icon.png', 512);
await renderPng('app_icon.png', 512);
await renderPng('ohos/AppScope/resources/base/media/app_icon.png', 512);
await renderPng('ohos/entry/src/main/resources/base/media/icon.png', 512);

const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const icoImages = await Promise.all(
  icoSizes.map((size) =>
    sharp(source).resize(size, size, { fit: 'contain' }).png().toBuffer(),
  ),
);
const icoHeader = Buffer.alloc(6 + icoImages.length * 16);
icoHeader.writeUInt16LE(0, 0);
icoHeader.writeUInt16LE(1, 2);
icoHeader.writeUInt16LE(icoImages.length, 4);
let icoOffset = icoHeader.length;
for (let index = 0; index < icoImages.length; index += 1) {
  const entryOffset = 6 + index * 16;
  const size = icoSizes[index];
  const image = icoImages[index];
  icoHeader.writeUInt8(size === 256 ? 0 : size, entryOffset);
  icoHeader.writeUInt8(size === 256 ? 0 : size, entryOffset + 1);
  icoHeader.writeUInt8(0, entryOffset + 2);
  icoHeader.writeUInt8(0, entryOffset + 3);
  icoHeader.writeUInt16LE(1, entryOffset + 4);
  icoHeader.writeUInt16LE(32, entryOffset + 6);
  icoHeader.writeUInt32LE(image.length, entryOffset + 8);
  icoHeader.writeUInt32LE(icoOffset, entryOffset + 12);
  icoOffset += image.length;
}
await writeFile(
  path.join(projectDir, 'windows/runner/resources/app_icon.ico'),
  Buffer.concat([icoHeader, ...icoImages]),
);

await copyFile(sourceSvg, path.join(projectDir, 'doubao_nomark.svg'));

for (const { output, size } of generatedPngs) {
  const metadata = await sharp(output).metadata();
  if (metadata.width !== size || metadata.height !== size) {
    throw new Error(`Unexpected dimensions for ${output}`);
  }
  const { data, info } = await sharp(output)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  let visible = false;
  for (let offset = 3; offset < data.length; offset += info.channels) {
    if (data[offset] !== 0) {
      visible = true;
      break;
    }
  }
  if (!visible || (await stat(output)).size === 0) {
    throw new Error(`Empty icon output: ${output}`);
  }
}

const ico = await readFile(
  path.join(projectDir, 'windows/runner/resources/app_icon.ico'),
);
if (ico.readUInt16LE(2) !== 1 || ico.readUInt16LE(4) !== icoSizes.length) {
  throw new Error('Invalid Windows ICO header');
}

console.log(
  `Generated ${generatedPngs.length} PNG icons and ${icoSizes.length}-size ICO from ${sourceSvg}`,
);
