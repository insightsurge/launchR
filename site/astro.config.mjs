import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://launchr.example.com',
  integrations: [sitemap()],
  devToolbar: { enabled: false },
});
