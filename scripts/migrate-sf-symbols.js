#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const SF_SYMBOLS_DIR = path.join(__dirname, '../web/src/assets/sf-symbols');
const IMPORT_SCRIPT = path.join(__dirname, 'import-sf-symbols.js');

function getAllTsxFiles(dir, fileList = []) {
  const files = fs.readdirSync(dir);

  for (const file of files) {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);

    if (stat.isDirectory()) {
      getAllTsxFiles(filePath, fileList);
    } else if (file.endsWith('.tsx')) {
      fileList.push(filePath);
    }
  }

  return fileList;
}

function extractIconName(filePath) {
  const relativePath = path.relative(SF_SYMBOLS_DIR, filePath);
  const fileName = path.basename(relativePath, '.tsx');
  return fileName;
}

function main() {
  if (!fs.existsSync(SF_SYMBOLS_DIR)) {
    console.error(`Directory does not exist: ${SF_SYMBOLS_DIR}`);
    process.exit(1);
  }

  console.log(`Scanning ${SF_SYMBOLS_DIR} for .tsx files...`);

  const tsxFiles = getAllTsxFiles(SF_SYMBOLS_DIR);
  const iconNames = new Set();

  for (const file of tsxFiles) {
    const iconName = extractIconName(file);
    iconNames.add(iconName);
  }

  if (iconNames.size === 0) {
    console.log('No .tsx files found.');
    return;
  }

  console.log(`Found ${iconNames.size} unique icon(s) to migrate:`);
  for (const iconName of iconNames) {
    console.log(`  - ${iconName}`);
  }

  console.log('\nStarting migration...\n');

  let successCount = 0;
  let errorCount = 0;

  for (const iconName of iconNames) {
    try {
      console.log(`Migrating ${iconName}...`);
      execSync(`node "${IMPORT_SCRIPT}" "${iconName}"`, {
        stdio: 'inherit',
        cwd: __dirname,
      });
      console.log(`✓ Successfully migrated ${iconName}\n`);
      successCount++;
    } catch (error) {
      console.error(`\n✗ Failed to migrate ${iconName}`);
      errorCount++;
    }
  }

  console.log(`\nMigration complete. Success: ${successCount}, Errors: ${errorCount}`);
}

main();

