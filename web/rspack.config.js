import path from 'path';
import { fileURLToPath } from 'url';
import rspack from '@rspack/core';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const loaders = [
  {
    test: /\.tsx?$/,
    exclude: /(node_modules|\.webpack)/,
    use: {
      loader: 'builtin:swc-loader',
      options: {
        jsc: {
          parser: {
            syntax: 'typescript',
            tsx: true,
          },
          transform: {
            react: {
              runtime: 'automatic',
            },
          },
        },
      },
    },
  },
  {
    test: /\.css$/,
    use: ['style-loader', 'css-loader', 'postcss-loader'],
    type: 'javascript/auto',
  },
];

const devAllowedHosts = 'all';

function UpperFirst(name) {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

function embeddedEntry(name, options = {}) {
  const { devServerPort, writeToDisk } = options;
  return {
    name: name,
    entry: {
      main: `./src/embedded/${name}/index.tsx`,
    },
    devtool: false,
    output: {
      path: path.resolve(
        __dirname,
        '..',
        'macos/OpenBridge/Helpers/WebKitBridgeUI/WebKitBridgeResources',
        `${UpperFirst(name)}Assets`
      ),
      filename: `${name}.js`,
      clean: true,
    },
    resolve: {
      extensions: ['.tsx', '.ts', '.js'],
      alias: {
        '@': path.resolve(__dirname, 'src'),
      },
    },
    module: {
      rules: loaders,
    },
    plugins: [
      new rspack.HtmlRspackPlugin({
        template: './src/index.html',
        filename: `${name}.html`,
      }),
    ],
    devServer: {
      allowedHosts: devAllowedHosts,
      compress: true,
      port: devServerPort,
      hot: true,
      historyApiFallback: {
        index: `/${name}.html`,
      },
      devMiddleware: {
        writeToDisk: writeToDisk,
      },
    },
  };
}

export default [
  embeddedEntry('chat', { devServerPort: 8083, writeToDisk: false }),
  embeddedEntry('preview', { devServerPort: 8085, writeToDisk: false }),
];
