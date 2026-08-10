import type { NextConfig } from 'next'

// Static export: the landing page has no server-side logic, so we
// generate plain HTML/CSS/JS and serve it from any static host.
const nextConfig: NextConfig = {
  output: 'export',
}

export default nextConfig
