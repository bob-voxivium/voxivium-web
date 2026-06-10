import { defineConfig } from 'astro/config'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  site: 'https://voxivium.com',
  integrations: [
    sitemap({
      filter: (page) => !page.includes('/kickstarter'),
    }),
  ],
  prefetch: true,
  vite: {
    plugins: [tailwindcss()],
  },
})
