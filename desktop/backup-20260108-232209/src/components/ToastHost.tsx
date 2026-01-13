import { useEffect } from 'react'
import { clsx } from 'clsx'
import { useAppStore } from '../stores/appStore'

export function ToastHost() {
  const toast = useAppStore((state) => state.toast)
  const clearToast = useAppStore((state) => state.clearToast)

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => {
      clearToast()
    }, 2500)
    return () => window.clearTimeout(timer)
  }, [toast, clearToast])

  if (!toast) return null

  return (
    <div className="fixed top-4 right-4 z-50">
      <div
        className={clsx(
          'text-white text-sm px-4 py-2 rounded-lg shadow-lg',
          toast.kind === 'success' ? 'bg-green-600' : 'bg-red-600'
        )}
      >
        {toast.message}
      </div>
    </div>
  )
}
