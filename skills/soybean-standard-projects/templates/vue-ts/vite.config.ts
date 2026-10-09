import { defineConfig } from 'vite-plus';
import { lint, fmt } from '@soybeanjs/oxc-config';
import vue from '@vitejs/plugin-vue';
import vueJsx from '@vitejs/plugin-vue-jsx';

export default defineConfig({
  staged: {
    '*': 'vp check --fix'
  },
  lint,
  fmt: {
    ...fmt,
    ignorePatterns: ['CHANGELOG.md']
  },
  resolve: {
    tsconfigPaths: true
  },
  plugins: [vue(), vueJsx()]
});
