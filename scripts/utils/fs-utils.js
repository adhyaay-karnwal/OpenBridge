const fs = require('fs');

/**
 * Ensure a directory exists, create if not
 * @param {string} dirPath - Path to the directory
 */
function ensureDirectoryExists(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

/**
 * Check if a file exists
 * @param {string} filePath - Path to the file
 * @returns {boolean}
 */
function fileExists(filePath) {
  return fs.existsSync(filePath);
}

/**
 * Read file content as string
 * @param {string} filePath - Path to the file
 * @param {string} encoding - File encoding (default: 'utf8')
 * @returns {string}
 */
function readFileContent(filePath, encoding = 'utf8') {
  return fs.readFileSync(filePath, encoding);
}

/**
 * Write content to a file
 * @param {string} filePath - Path to the file
 * @param {string} content - Content to write
 * @param {string} encoding - File encoding (default: 'utf8')
 */
function writeFileContent(filePath, content, encoding = 'utf8') {
  fs.writeFileSync(filePath, content, encoding);
}

/**
 * Read and parse a JSON file
 * @param {string} filePath - Path to the JSON file
 * @param {*} defaultValue - Default value if file doesn't exist or parse fails
 * @returns {*}
 */
function readJsonFile(filePath, defaultValue = null) {
  try {
    if (!fs.existsSync(filePath)) {
      return defaultValue;
    }
    const content = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(content);
  } catch {
    return defaultValue;
  }
}

module.exports = {
  ensureDirectoryExists,
  fileExists,
  readFileContent,
  writeFileContent,
  readJsonFile,
};

