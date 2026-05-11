const fs = require('fs');
const https = require('https');
const http = require('http');

/**
 * Format bytes to human readable string
 * @param {number} bytes
 * @returns {string}
 */
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

/**
 * Download a file with progress display
 * @param {string} url - URL to download from
 * @param {string} destPath - Destination file path
 * @param {Object} options - Download options
 * @param {number} options.maxRedirects - Maximum number of redirects (default: 10)
 * @param {boolean} options.silent - Suppress progress output (default: false)
 * @returns {Promise<void>}
 */
function downloadWithProgress(url, destPath, options = {}) {
  const { maxRedirects = 10, silent = false } = options;

  return new Promise((resolve, reject) => {
    let redirectCount = 0;

    const doRequest = (requestUrl) => {
      const protocol = requestUrl.startsWith('https://') ? https : http;

      protocol
        .get(requestUrl, (response) => {
          if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
            redirectCount++;
            if (redirectCount > maxRedirects) {
              reject(new Error('Too many redirects'));
              return;
            }
            const redirectUrl = response.headers.location;
            doRequest(redirectUrl);
            return;
          }

          if (response.statusCode !== 200) {
            reject(new Error(`Failed to download: HTTP ${response.statusCode}`));
            return;
          }

          const file = fs.createWriteStream(destPath);
          const totalSize = parseInt(response.headers['content-length'], 10);
          let downloadedSize = 0;

          response.on('data', (chunk) => {
            downloadedSize += chunk.length;
            file.write(chunk);

            if (!silent) {
              if (totalSize) {
                const percent = ((downloadedSize / totalSize) * 100).toFixed(1);
                const downloaded = formatBytes(downloadedSize);
                const total = formatBytes(totalSize);
                process.stdout.write(`\rDownloading: ${percent}% (${downloaded} / ${total})`);
              } else {
                process.stdout.write(`\rDownloading: ${formatBytes(downloadedSize)}`);
              }
            }
          });

          response.on('end', () => {
            file.end(() => {
              if (!silent) {
                process.stdout.write('\n');
                console.log('Download completed.');
              }
              resolve();
            });
          });

          response.on('error', (err) => {
            file.close();
            fs.unlink(destPath, () => {});
            reject(new Error(`Failed to download: ${err.message}`));
          });

          file.on('error', (err) => {
            fs.unlink(destPath, () => {});
            reject(new Error(`Failed to write file: ${err.message}`));
          });
        })
        .on('error', (err) => {
          fs.unlink(destPath, () => {});
          reject(new Error(`Failed to download: ${err.message}`));
        });
    };

    doRequest(url);
  });
}

/**
 * Ensure a file exists, download if not
 * @param {string} filePath - Path to the file
 * @param {string} downloadUrl - URL to download from if file doesn't exist
 * @param {Object} options - Download options (passed to downloadWithProgress)
 * @returns {Promise<void>}
 */
async function ensureFileExists(filePath, downloadUrl, options = {}) {
  if (fs.existsSync(filePath)) {
    return;
  }

  console.log(`File not found. Downloading from ${downloadUrl}...`);
  await downloadWithProgress(downloadUrl, filePath, options);
}

module.exports = {
  formatBytes,
  downloadWithProgress,
  ensureFileExists,
};

