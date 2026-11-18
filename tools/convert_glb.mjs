#!/usr/bin/env node
/**
 * Converts CS2GO .glb / .glb.gz files that use EXT_meshopt_compression,
 * KHR_mesh_quantization, or KHR_texture_basisu (KTX2) into standard
 * uncompressed glTF 2.0 .glb (or .glb.gz) files with WebP textures that
 * Godot 4.3+ imports natively.
 *
 * Usage:
 *   node convert_glb.mjs <input.glb|input.glb.gz> <output.glb|output.glb.gz>
 *   node convert_glb.mjs --batch <manifest.json>
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { NodeIO } from '@gltf-transform/core';
import { KHRONOS_EXTENSIONS, EXTMeshoptCompression, EXTTextureWebP } from '@gltf-transform/extensions';
import { dedup, dequantize, prune } from '@gltf-transform/functions';
import { MeshoptDecoder } from 'meshoptimizer';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

function loadBasisFactory() {
  const jsPath = path.join(__dirname, 'node_modules/three/examples/jsm/libs/basis/basis_transcoder.js');
  const tmpCjs = path.join(__dirname, '.cache', 'basis_transcoder.cjs');
  fs.mkdirSync(path.dirname(tmpCjs), { recursive: true });
  if (!fs.existsSync(tmpCjs)) {
    fs.copyFileSync(jsPath, tmpCjs);
  }
  return {
    BASIS: require(tmpCjs),
    wasmPath: path.join(__dirname, 'node_modules/three/examples/jsm/libs/basis/basis_transcoder.wasm'),
  };
}

function readGlbExtensions(buf) {
  if (buf.length < 20) return { used: [], req: [] };
  const chunkLen = buf.readUInt32LE(12);
  try {
    const gltf = JSON.parse(buf.subarray(20, 20 + chunkLen).toString('utf8'));
    return {
      used: gltf.extensionsUsed || [],
      req: gltf.extensionsRequired || [],
    };
  } catch {
    return { used: [], req: [] };
  }
}

async function createContext() {
  const { BASIS, wasmPath } = loadBasisFactory();
  const wasmBinary = fs.readFileSync(wasmPath);
  const basis = await BASIS({ wasmBinary });
  basis.initializeBasis();

  await MeshoptDecoder.ready;
  const io = new NodeIO()
    .registerExtensions([...KHRONOS_EXTENSIONS, EXTMeshoptCompression, EXTTextureWebP])
    .registerDependencies({ 'meshopt.decoder': MeshoptDecoder });

  return { basis, io };
}

async function reencodeImageToWebp(imgBytes, maxSize, quality = 76) {
  let pipeline = sharp(Buffer.from(imgBytes));
  if (maxSize > 0) {
    const meta = await pipeline.metadata();
    if ((meta.width && meta.width > maxSize) || (meta.height && meta.height > maxSize)) {
      pipeline = pipeline.resize(maxSize, maxSize, { fit: 'inside', withoutEnlargement: true });
    }
  }
  return await pipeline.webp({ quality }).toBuffer();
}

async function convertOne(ctx, inputPath, outputPath, opts = {}) {
  const stripExtraAttrs = !!opts.stripExtraAttrs;
  const maxTextureSize = opts.maxTextureSize || 0;

  let raw = fs.readFileSync(inputPath);
  if (inputPath.endsWith('.gz')) {
    raw = zlib.gunzipSync(raw);
  }
  const { used, req } = readGlbExtensions(raw);
  const needsConversion =
    used.includes('EXT_meshopt_compression') ||
    used.includes('KHR_texture_basisu') ||
    req.includes('EXT_meshopt_compression') ||
    req.includes('KHR_texture_basisu') ||
    req.includes('KHR_mesh_quantization') ||
    stripExtraAttrs ||
    maxTextureSize > 0;

  fs.mkdirSync(path.dirname(outputPath), { recursive: true });

  let outBuf;
  let ktxCount = 0;
  let status = 'copied';

  if (!needsConversion) {
    outBuf = raw;
  } else {
    status = 'converted';
    const doc = await ctx.io.readBinary(new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength));
    let hasWebP = false;

    for (const tex of doc.getRoot().listTextures()) {
      const mime = tex.getMimeType();
      const img = tex.getImage();
      if (!img) continue;

      if (mime === 'image/ktx2') {
        const ktx2File = new ctx.basis.KTX2File(img);
        if (!ktx2File.isValid()) {
          ktx2File.close();
          ktx2File.delete();
          continue;
        }
        const width = ktx2File.getWidth();
        const height = ktx2File.getHeight();
        if (!ktx2File.startTranscoding()) {
          ktx2File.close();
          ktx2File.delete();
          throw new Error(`startTranscoding failed for ${tex.getName()}`);
        }
        const fmt = ctx.basis.transcoder_texture_format.cTFRGBA32.value;
        const dstSize = ktx2File.getImageTranscodedSizeInBytes(0, 0, 0, fmt);
        const dst = new Uint8Array(dstSize);
        const ok = ktx2File.transcodeImage(dst, 0, 0, 0, fmt, 0, -1, -1);
        ktx2File.close();
        ktx2File.delete();
        if (!ok) throw new Error(`transcodeImage failed for ${tex.getName()}`);

        let pipe = sharp(Buffer.from(dst), { raw: { width, height, channels: 4 } });
        if (maxTextureSize > 0 && (width > maxTextureSize || height > maxTextureSize)) {
          pipe = pipe.resize(maxTextureSize, maxTextureSize, { fit: 'inside', withoutEnlargement: true });
        }
        const webpBuf = await pipe.webp({ quality: 78 }).toBuffer();
        tex.setImage(new Uint8Array(webpBuf));
        tex.setMimeType('image/webp');
        hasWebP = true;
        ktxCount++;
      } else if (mime === 'image/webp' || mime === 'image/png' || mime === 'image/jpeg') {
        if (maxTextureSize > 0) {
          const webpBuf = await reencodeImageToWebp(img, maxTextureSize, 76);
          if (webpBuf.length < img.length || mime !== 'image/webp') {
            tex.setImage(new Uint8Array(webpBuf));
            tex.setMimeType('image/webp');
          }
          hasWebP = true;
        } else if (mime === 'image/webp') {
          hasWebP = true;
        }
      }
    }

    if (hasWebP) {
      doc.createExtension(EXTTextureWebP).setRequired(true);
    }

    if (stripExtraAttrs) {
      for (const mesh of doc.getRoot().listMeshes()) {
        for (const prim of mesh.listPrimitives()) {
          for (const sem of prim.listSemantics()) {
            if (/^COLOR_[1-9]/.test(sem) || /^TEXCOORD_[2-9]/.test(sem)) {
              prim.setAttribute(sem, null);
            }
          }
        }
      }
    }

    await doc.transform(dedup(), prune(), dequantize());
    for (const ext of doc.getRoot().listExtensionsUsed()) {
      if (ext.extensionName === 'EXT_meshopt_compression' || ext.extensionName === 'KHR_texture_basisu') {
        ext.dispose();
      }
    }
    const glbArr = await ctx.io.writeBinary(doc);
    outBuf = Buffer.from(glbArr.buffer, glbArr.byteOffset, glbArr.byteLength);
  }

  if (outputPath.endsWith('.gz')) {
    outBuf = zlib.gzipSync(outBuf, { level: 9 });
  }
  fs.writeFileSync(outputPath, outBuf);
  return { status, ktx2: ktxCount, bytes: outBuf.length };
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--batch') {
    const manifest = JSON.parse(fs.readFileSync(args[1], 'utf8'));
    const ctx = await createContext();
    let totalBytes = 0;
    for (const item of manifest) {
      const res = await convertOne(ctx, item.input, item.output, item);
      totalBytes += res.bytes;
      console.log(`[${res.status}] ${path.basename(item.output)} (${(res.bytes / 1048576).toFixed(2)} MB, ktx2->webp: ${res.ktx2})`);
    }
    console.log(`Total output size: ${(totalBytes / 1048576).toFixed(2)} MB`);
    return;
  }
  if (args.length < 2) {
    console.error('Usage: node convert_glb.mjs <input.glb[.gz]> <output.glb[.gz]>');
    process.exit(1);
  }
  const ctx = await createContext();
  const res = await convertOne(ctx, args[0], args[1], { stripExtraAttrs: args.includes('--strip-cs2') });
  console.log(`[${res.status}] ${args[1]} (${(res.bytes / 1048576).toFixed(2)} MB, ktx2->webp: ${res.ktx2})`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
