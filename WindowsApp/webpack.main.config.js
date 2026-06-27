/* eslint-disable @typescript-eslint/no-var-requires */
const path = require('path');

/** @type {import('webpack').Configuration} */
module.exports = {
  mode: process.env.NODE_ENV === 'production' ? 'production' : 'development',
  target: 'electron-main',
  entry: {
    index: './src/main/index.ts',
  },
  output: {
    path: path.resolve(__dirname, 'dist/main'),
    filename: '[name].js',
  },
  resolve: {
    extensions: ['.ts', '.js'],
    alias: {
      '@shared': path.resolve(__dirname, 'src/shared'),
    },
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: 'ts-loader',
        exclude: /node_modules/,
      },
      {
        test: /\.node$/,
        use: 'node-loader',
      },
    ],
  },
  externals: {
    // Keep native addon external (not bundled by webpack).
    './native/ndi_addon.node': 'commonjs ./native/ndi_addon.node',
  },
  devtool: 'source-map',
  node: {
    __dirname: false,
    __filename: false,
  },
};
