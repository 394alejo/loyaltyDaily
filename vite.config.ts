import path from 'path';
import fs from 'fs';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const copy404Plugin = {
  name: 'copy-index-to-404',
  closeBundle() {
    if (fs.existsSync('dist/index.html')) {
      fs.copyFileSync('dist/index.html', 'dist/404.html');
    }
  }
};

export default defineConfig(({ mode }) => {
    return {
      server: {
        port: 3000,
        host: '0.0.0.0',
      },
      plugins: [react(), copy404Plugin],
      resolve: {
        alias: {
          '@': path.resolve(__dirname, '.'),
        }
      }
    };
});
