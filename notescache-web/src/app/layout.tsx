import type { Metadata, Viewport } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'NotesCache — Many notes. One place.',
  description: 'Your campus study companion. Browse notes, read documents, and get AI study help. Download the app or use the website.',
  manifest: '/manifest.webmanifest',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: 'NotesCache',
  },
  icons: {
    apple: '/icon-192.png',
    icon: '/icon-192.png',
  },
}

export const viewport: Viewport = {
  themeColor: '#4F46E5',
  width: 'device-width',
  initialScale: 1,
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <meta name="apple-mobile-web-app-capable" content="yes" />
        <meta name="apple-mobile-web-app-status-bar-style" content="default" />
        <meta name="mobile-web-app-capable" content="yes" />
        <link rel="apple-touch-icon" href="/icon-192.png" />
      </head>
      <body>
        {children}
        <script
          dangerouslySetInnerHTML={{
            __html: `
              // Service worker: only in production. In dev (localhost) the
              // cache-first SW serves stale HTML with dead chunk URLs, which
              // loops the page. Also unregister any stale SW + clear its cache.
              if ('serviceWorker' in navigator) {
                var isDev = ['localhost', '127.0.0.1'].indexOf(window.location.hostname) !== -1;
                window.addEventListener('load', function () {
                  if (isDev) {
                    navigator.serviceWorker.getRegistrations().then(function (regs) {
                      regs.forEach(function (r) { r.unregister(); });
                    });
                    if (window.caches) {
                      window.caches.keys().then(function (keys) {
                        keys.forEach(function (k) { window.caches.delete(k); });
                      });
                    }
                    return;
                  }
                  navigator.serviceWorker.register('/sw.js').catch(function (e) {
                    console.warn('SW registration failed', e);
                  });
                });
              }
            `,
          }}
        />
      </body>
    </html>
  )
}
