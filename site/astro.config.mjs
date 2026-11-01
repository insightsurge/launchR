import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://launch-r.web.app',
  integrations: [sitemap()],
  devToolbar: { enabled: false },
});
