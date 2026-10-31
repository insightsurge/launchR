import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://r-pkg-kit.example.com',
  integrations: [sitemap()],
  devToolbar: { enabled: false },
});
