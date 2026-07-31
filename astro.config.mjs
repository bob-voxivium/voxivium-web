import { defineConfig } from 'astro/config'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  site: 'https://voxivium.com',
  integrations: [
    sitemap({
      // Keep transactional and dormant routes out. /subscribe and
      // /subscribe/complete are noindexed in the page head; listing them here
      // would ask Google to crawl pages we've told it not to index.
      filter: (page) =>
        !page.includes('/kickstarter') &&
        !page.includes('/subscribe') &&
        !page.includes('/404'),
      // A single build timestamp. Honest at the granularity we have: this is a
      // static site rebuilt on deploy, and per-page mtimes would be lost
      // through CI checkouts anyway.
      lastmod: new Date(),
      changefreq: 'weekly',
      serialize(item) {
        // Home is the entry point and the page most worth recrawling.
        if (item.url === 'https://voxivium.com/') {
          return { ...item, priority: 1.0, changefreq: 'weekly' }
        }
        // Legal text changes rarely; don't spend crawl budget on it.
        if (item.url.includes('/legal/')) {
          return { ...item, priority: 0.3, changefreq: 'yearly' }
        }
        if (item.url.includes('/insights')) {
          return { ...item, priority: 0.8, changefreq: 'monthly' }
        }
        return { ...item, priority: 0.7 }
      },
    }),
  ],
  prefetch: true,
  vite: {
    plugins: [tailwindcss()],
  },
})
