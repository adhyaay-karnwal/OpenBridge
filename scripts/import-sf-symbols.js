const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { ensureFileExists, ensureDirectoryExists, readJsonFile } = require('./utils');

// Configuration
const ZIP_FILE = path.join(__dirname, 'sf-symbols.zip');
const ZIP_DOWNLOAD_URL = 'https://cdn.bridge.surf/sf-symbols.zip';
const OUTPUT_BASE_DIR = path.join(__dirname, '../web/src/assets/sf-symbols');
const PRETTIER_CONFIG = path.join(__dirname, '../web/.prettierrc');

function readFileHeader(filePath, length = 512) {
  const fd = fs.openSync(filePath, 'r');

  try {
    const buffer = Buffer.alloc(length);
    const bytesRead = fs.readSync(fd, buffer, 0, length, 0);
    return buffer.subarray(0, bytesRead);
  } finally {
    fs.closeSync(fd);
  }
}

function validateZipFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return { valid: false, reason: 'missing' };
  }

  const header = readFileHeader(filePath);
  const isZip =
    header.length >= 4 &&
    header[0] === 0x50 &&
    header[1] === 0x4b &&
    (header[2] === 0x03 || header[2] === 0x05 || header[2] === 0x07) &&
    (header[3] === 0x04 || header[3] === 0x06 || header[3] === 0x08);

  if (isZip) {
    return { valid: true };
  }

  const headerText = header.toString('utf8').toLowerCase();
  if (headerText.includes('<!doctype html') || headerText.includes('<html')) {
    if (headerText.includes('cloudflare access')) {
      return { valid: false, reason: 'cloudflare-access' };
    }

    return { valid: false, reason: 'html' };
  }

  return { valid: false, reason: 'invalid' };
}

function buildZipValidationError(validation) {
  switch (validation.reason) {
    case 'missing':
      return `SF Symbols archive is missing at ${ZIP_FILE}.`;
    case 'cloudflare-access':
      return (
        `Downloaded ${ZIP_FILE}, but it contains a Cloudflare Access sign-in page instead of a zip archive. ` +
        `Authenticate to https://cdn.bridge.surf/sf-symbols.zip and re-run, or replace ${ZIP_FILE} with a valid archive.`
      );
    case 'html':
      return (
        `Downloaded ${ZIP_FILE}, but it contains HTML instead of a zip archive. ` +
        `Replace the file with a valid SF Symbols archive and re-run the script.`
      );
    default:
      return `Downloaded ${ZIP_FILE}, but it is not a valid zip archive.`;
  }
}

// Download ZIP file if not exists
async function ensureZipFile() {
  const existingValidation = validateZipFile(ZIP_FILE);
  if (!existingValidation.valid && existingValidation.reason !== 'missing') {
    console.warn(`Existing SF Symbols archive is invalid (${existingValidation.reason}). Re-downloading...`);
    fs.unlinkSync(ZIP_FILE);
  }

  await ensureFileExists(ZIP_FILE, ZIP_DOWNLOAD_URL);

  const finalValidation = validateZipFile(ZIP_FILE);
  if (!finalValidation.valid) {
    throw new Error(buildZipValidationError(finalValidation));
  }
}

// Utility functions
function toPascalCase(str) {
  return str
    .replace(/[-.]+(\w)/g, (_, c) => c.toUpperCase())
    .replace(/^(\w)/, (_, c) => c.toUpperCase());
}

function toPascalCaseWeight(weight) {
  return weight.charAt(0).toUpperCase() + weight.slice(1).toLowerCase();
}

function parseSvg(content) {
  const viewBoxMatch = content.match(/viewBox="([^"]+)"/);
  const viewBox = viewBoxMatch ? viewBoxMatch[1] : '0 0 24 24';

  const innerContentMatch = content.match(/<svg[^>]*>([\s\S]*?)<\/svg>/);
  let innerContent = innerContentMatch ? innerContentMatch[1] : '';

  innerContent = innerContent
    .replace(/<\?xml.*?\?>/g, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\s*fill-opacity="0\.85"\s*/g, ' ')
    .replace(/\s*fill-opacity='0\.85'\s*/g, ' ')
    .replace(/fill="currentColor"/g, 'fill="currentColor"')
    .replace(/fill="[^"]*"/g, 'fill="currentColor"')
    .replace(/\s{2,}/g, ' ');

  return { viewBox, innerContent };
}

async function formatWithPrettier(content) {
  if (typeof content !== 'string') {
    throw new Error('Content must be a string');
  }

  try {
    const webDir = path.join(__dirname, '../web');
    const prettierPath = path.join(webDir, 'node_modules/prettier');
    let prettier;
    try {
      prettier = require(prettierPath);
    } catch (requireError) {
      prettier = require('prettier');
    }

    if (!prettier || typeof prettier.format !== 'function') {
      throw new Error('Prettier format function not available');
    }

    const config = readJsonFile(PRETTIER_CONFIG, {});

    const formatOptions = {
      ...config,
      parser: 'babel-ts',
    };

    const result = await prettier.format(content, formatOptions);

    if (!result) {
      throw new Error('Prettier format returned empty result');
    }

    if (typeof result !== 'string') {
      throw new Error(`Prettier format returned ${typeof result}, expected string`);
    }

    return result;
  } catch (error) {
    throw new Error(`Failed to format with prettier: ${error.message}`);
  }
}

function listFilesInZip() {
  try {
    const output = execSync(`unzip -Z1 "${ZIP_FILE}"`, {
      encoding: 'utf8',
      maxBuffer: 50 * 1024 * 1024, // 50MB buffer for large zip files
    });
    return output.split('\n').filter((line) => line.trim().endsWith('.svg'));
  } catch (error) {
    throw new Error(`Failed to list files in zip: ${error.message}`);
  }
}

function extractFileFromZip(filePath) {
  try {
    return execSync(`unzip -p "${ZIP_FILE}" "${filePath}"`, {
      encoding: 'utf8',
      maxBuffer: 10 * 1024 * 1024, // 10MB buffer for SVG files
    });
  } catch (error) {
    throw new Error(`Failed to extract ${filePath}: ${error.message}`);
  }
}

function parseFilePath(filePath) {
  const match = filePath.match(/^sf-symbols\/([^/]+)\/(.+)\.svg$/);
  if (!match) {
    return null;
  }
  return {
    weight: match[1],
    iconName: match[2],
  };
}

async function generateComponent(iconName, weight, viewBox, innerContent) {
  const componentName = `${toPascalCase(iconName)}SFSymbol${toPascalCaseWeight(weight)}`;
  const componentContent = `import type { SVGProps } from "react";

export const ${componentName} = (props: SVGProps<SVGSVGElement>) => {
  return (
    <svg
      height="1em"
      version="1.1"
      xmlns="http://www.w3.org/2000/svg"
      xmlnsXlink="http://www.w3.org/1999/xlink"
      viewBox="${viewBox}"
      fill="currentColor"
      {...props}
    >
      ${innerContent.trim()}
    </svg>
  );
};
`;

  return await formatWithPrettier(componentContent);
}

async function searchIcons(searchTerm) {
  await ensureZipFile();

  const files = listFilesInZip();
  const matches = files.filter((file) => {
    const parsed = parseFilePath(file);
    return parsed && (parsed.iconName.includes(searchTerm) || parsed.weight.includes(searchTerm));
  });

  if (matches.length === 0) {
    console.log(`No icons found matching "${searchTerm}".`);
    return;
  }

  console.log(`Found ${matches.length} icons matching "${searchTerm}":`);
  const grouped = {};
  for (const file of matches) {
    const parsed = parseFilePath(file);
    if (parsed) {
      if (!grouped[parsed.iconName]) {
        grouped[parsed.iconName] = [];
      }
      grouped[parsed.iconName].push(parsed.weight);
    }
  }

  for (const [iconName, weights] of Object.entries(grouped)) {
    console.log(`- ${iconName} (weights: ${weights.join(', ')})`);
  }
}

async function importIcons(targetIcons, importAll) {
  await ensureZipFile();

  console.log(`Reading SVGs from: ${ZIP_FILE}`);

  let files = listFilesInZip();
  const parsedFiles = files.map((file) => parseFilePath(file)).filter(Boolean);

  if (!importAll) {
    const filtered = parsedFiles.filter((parsed) => {
      return targetIcons.some((target) => {
        return parsed.iconName === target;
      });
    });

    if (filtered.length === 0) {
      console.log(`No matching SVG files found for: ${targetIcons.join(', ')}`);
      return;
    }
    parsedFiles.length = 0;
    parsedFiles.push(...filtered);
  }

  if (parsedFiles.length === 0) {
    console.log('No SVG files found in zip.');
    return;
  }

  console.log(`Found ${parsedFiles.length} SVG files to import.`);

  let successCount = 0;
  let errorCount = 0;

  for (const parsed of parsedFiles) {
    try {
      const filePath = `sf-symbols/${parsed.weight}/${parsed.iconName}.svg`;
      const content = extractFileFromZip(filePath);
      const { viewBox, innerContent } = parseSvg(content);

      if (!innerContent.trim()) {
        console.warn(`Skipping ${filePath}: Could not extract content.`);
        errorCount++;
        continue;
      }

      const outputDir = path.join(OUTPUT_BASE_DIR, parsed.weight);
      ensureDirectoryExists(outputDir);

      const outputFileName = `${parsed.iconName}.tsx`;
      const outputPath = path.join(outputDir, outputFileName);

      const componentContent = await generateComponent(
        parsed.iconName,
        parsed.weight,
        viewBox,
        innerContent
      );

      fs.writeFileSync(outputPath, componentContent);
      console.log(`Generated ${parsed.weight}/${outputFileName}`);
      successCount++;
    } catch (error) {
      console.error(`Failed to process ${parsed.iconName} (${parsed.weight}):`, error.message);
      errorCount++;
    }
  }

  console.log(`\nDone. Success: ${successCount}, Errors: ${errorCount}`);
}

function showUsage() {
  console.log(`
Usage:
  node scripts/import-sf-symbols.js <icon-name> [icon-name-2 ...] [--all]
  node scripts/import-sf-symbols.js --search <term>

Examples:
  node scripts/import-sf-symbols.js house.fill
  node scripts/import-sf-symbols.js --search arrow
  node scripts/import-sf-symbols.js --all

Source Zip: ${ZIP_FILE}
Output Directory: ${OUTPUT_BASE_DIR}
`);
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    showUsage();
    return;
  }

  const searchIndex = args.findIndex((arg) => arg === '--search' || arg === '-s');
  if (searchIndex !== -1) {
    const searchTerm = args[searchIndex + 1];
    if (!searchTerm) {
      console.error('Please provide a search term.');
      process.exit(1);
    }
    await searchIcons(searchTerm);
    return;
  }

  const importAll = args.includes('--all');
  const targetIcons = args.filter((arg) => !arg.startsWith('--'));

  if (!importAll && targetIcons.length === 0) {
    console.error('Please provide icon names or use --all flag.');
    process.exit(1);
  }

  await importIcons(targetIcons, importAll);
}

main().catch((error) => {
  console.error('Unhandled error:', error);
  process.exit(1);
});
