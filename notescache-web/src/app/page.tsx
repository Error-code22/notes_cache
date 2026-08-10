import Link from 'next/link'

const WHATSAPP_GROUP = 'https://chat.whatsapp.com/DkqyCtURIAiKOhEijE8rZT'
const WHATSAPP_SUPPORT = 'https://wa.me/254703300084'
const GITHUB_REPO = 'https://github.com/Error-code22/notes_cache'
const RELEASE_PAGE = 'https://github.com/Error-code22/notes_cache/releases'
// 'latest' auto-points to the newest release — no URL changes needed on updates
const APK_ARM64 = 'https://github.com/Error-code22/notes_cache/releases/latest/download/NotesCache-arm64-v8a.apk'
const APK_V7A = 'https://github.com/Error-code22/notes_cache/releases/latest/download/NotesCache-armeabi-v7a.apk'
const WIN_ZIP = 'https://github.com/Error-code22/notes_cache/releases/latest/download/NotesCache-Windows.zip'

export default function Home() {
  return (
    <div className="min-h-screen bg-gradient-to-b from-indigo-50 to-white">
      <header className="border-b bg-white/80 backdrop-blur-sm">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center justify-between">
          <h1 className="text-xl font-bold text-indigo-600">NotesCache</h1>
          <a
            href={GITHUB_REPO}
            target="_blank"
            rel="noopener noreferrer"
            className="px-4 py-2 text-indigo-600 hover:text-indigo-800 transition text-sm font-medium"
          >
            GitHub →
          </a>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-4 py-16">
        <div className="text-center">
          <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
            Your Campus Study Companion
          </h2>
          <p className="text-lg text-gray-600 mb-2">
            Access lecture notes, chat with classmates, and get AI-powered study help — all in one place.
          </p>
          <p className="text-sm text-indigo-600 font-semibold mb-10">
            📱 Android & 🖥️ Windows available now — full web version coming soon
          </p>

          <div className="bg-white rounded-2xl shadow-sm border p-8 max-w-lg mx-auto">
            <h3 className="text-xl font-semibold mb-2">Download the App</h3>
            <p className="text-sm text-gray-500 mb-6">
              Pick the APK for your phone. Android 7 or newer required.
            </p>
            <div className="flex flex-col gap-3">
              <a
                href={APK_ARM64}
                className="px-6 py-4 bg-indigo-600 text-white rounded-xl text-lg font-medium hover:bg-indigo-700 transition flex items-center justify-center gap-2"
              >
                <span>📲</span> Download for most phones (arm64)
              </a>
              <a
                href={APK_V7A}
                className="px-6 py-4 border border-indigo-600 text-indigo-600 rounded-xl text-lg font-medium hover:bg-indigo-50 transition flex items-center justify-center gap-2"
              >
                Download for older phones (32-bit)
              </a>
              <a
                href={WIN_ZIP}
                className="px-6 py-4 border border-gray-300 text-gray-700 rounded-xl text-lg font-medium hover:bg-gray-50 transition flex items-center justify-center gap-2"
              >
                <span>🖥️</span> Download for Windows (PC)
              </a>
              <a
                href={RELEASE_PAGE}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-gray-500 hover:text-indigo-600 transition"
              >
                All releases on GitHub →
              </a>
            </div>
            <p className="text-xs text-gray-400 mt-4">
              After download, open the file and allow "install from unknown sources" when prompted (Android).
            </p>
          </div>

          <div className="mt-10 grid sm:grid-cols-2 gap-4 max-w-lg mx-auto">
            <a
              href={WHATSAPP_GROUP}
              target="_blank"
              rel="noopener noreferrer"
              className="bg-green-50 border border-green-200 text-green-700 p-4 rounded-xl font-medium hover:bg-green-100 transition"
            >
              💬 Join the WhatsApp group
            </a>
            <a
              href={WHATSAPP_SUPPORT}
              target="_blank"
              rel="noopener noreferrer"
              className="bg-gray-50 border border-gray-200 text-gray-700 p-4 rounded-xl font-medium hover:bg-gray-100 transition"
            >
              🛟 Get support on WhatsApp
            </a>
          </div>
        </div>
      </main>

      <footer className="border-t bg-white mt-16">
        <div className="max-w-4xl mx-auto px-4 py-8 text-center text-gray-500 text-sm">
          NotesCache — built for students, by students.
        </div>
      </footer>
    </div>
  )
}
