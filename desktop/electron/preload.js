'use strict';
// Minimal preload — no special APIs needed since the app communicates
// entirely through the local HTTP server.
const { contextBridge } = require('electron');

contextBridge.exposeInMainWorld('electronApp', {
  platform: process.platform,
  version:  process.env.npm_package_version || '1.0.0',
});
