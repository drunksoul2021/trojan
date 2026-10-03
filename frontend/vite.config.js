import path, { resolve } from 'path'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import viteSvgIcons from 'vite-plugin-svg-icons'

export default defineConfig({
  base: './',
  define: {
    'process.platform': null,
    'process.version': null,
    __VUE_I18N_FULL_INSTALL__: true,
    __VUE_I18N_LEGACY_API__: true,
    __INTLIFY_PROD_DEVTOOLS__: false
  },
  plugins: [vue(), viteSvgIcons({iconDirs: [path.resolve(process.cwd(), 'src/icons/svg')], symbolId: 'icon-[name]'})],
  resolve: {alias: {'~': resolve(__dirname, './'), '@': resolve(__dirname, 'src')}, extensions: ['.js', '.ts', '.jsx', '.tsx', '.json', '.vue', '.mjs']},
  server: {host: '127.0.0.1', proxy: {'/api': {target: 'http://127.0.0.1:80', changeOrigin: true, rewrite: path => path.replace(/^\/api/, '')}}},
  build: {outDir: '../web/templates', emptyOutDir: true, assetsDir: 'static', minify: 'esbuild'}
})
