'use client'

export default function ConvertOverlay({
  open,
  label,
  detail,
  percent,
}: {
  open: boolean
  label: string
  detail?: string
  /** 0–100, or indeterminate if omitted */
  percent?: number
}) {
  if (!open) return null
  const pct = Math.max(0, Math.min(100, Math.round(percent ?? 0)))
  const indeterminate = percent == null

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-[#1C1C1E] rounded-3xl shadow-2xl w-full max-w-sm p-6 text-center">
        <div className="relative mx-auto w-14 h-14 mb-4">
          <div className="absolute inset-0 rounded-full border-4 border-indigo-100 dark:border-indigo-500/20" />
          <div className="absolute inset-0 rounded-full border-4 border-indigo-600 border-t-transparent animate-spin" />
        </div>
        <div className="font-bold text-gray-900 dark:text-white text-base mb-1">{label}</div>
        {detail && <p className="text-[13px] text-gray-500 dark:text-gray-400 mb-3">{detail}</p>}

        <div className="h-2 rounded-full bg-gray-100 dark:bg-white/10 overflow-hidden">
          {indeterminate ? (
            <div className="h-full w-1/3 rounded-full bg-indigo-600 animate-pulse" />
          ) : (
            <div
              className="h-full rounded-full bg-indigo-600 transition-[width] duration-200"
              style={{ width: `${pct}%` }}
            />
          )}
        </div>
        {!indeterminate && (
          <div className="mt-2 text-[11px] font-bold text-indigo-600 tabular-nums">{pct}%</div>
        )}
        <p className="mt-3 text-[11px] text-gray-400">
          Building a PDF from slides… large decks can take a minute.
        </p>
      </div>
    </div>
  )
}
