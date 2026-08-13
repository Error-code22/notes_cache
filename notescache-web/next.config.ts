import type { NextConfig } from 'next'

// Static export: the landing page has no server-side logic, so we
// generate plain HTML/CSS/JS and serve it from any static host.
const nextConfig: NextConfig = {
  output: 'export',
  // The repo root has a stray package-lock.json; point Turbopack at the
  // actual web app so it stops warning about the wrong workspace root.
  turbopack: {
    root: __dirname,
  },
}

export default nextConfig
