/**
 * ToastHost Component - Redesigned
 * Toast notification display
 */
import { useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { CheckCircle2, XCircle } from 'lucide-react'
import { useAppStore } from '../stores/appStore'

export function ToastHost() {
  const toast = useAppStore((state) => state.toast)
  const clearToast = useAppStore((state) => state.clearToast)

  useEffect(() => {
    if (!toast) return
    const timer = window.setTimeout(() => {
      clearToast()
    }, 3000)
    return () => window.clearTimeout(timer)
  }, [toast, clearToast])

  return (
    <AnimatePresence>
      {toast && (
        <motion.div
          initial={{ opacity: 0, y: -20, x: 20, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, x: 0, scale: 1 }}
          exit={{ opacity: 0, y: -10, scale: 0.95 }}
          transition={{ type: 'spring', damping: 25, stiffness: 300 }}
          className="fixed top-4 right-4 z-50"
        >
          <div
            className={`flex items-center gap-3 px-4 py-3 rounded-xl shadow-lg border backdrop-blur-sm ${
              toast.kind === 'success'
                ? 'bg-emerald-50 dark:bg-emerald-900/90 border-emerald-200 dark:border-emerald-800'
                : 'bg-red-50 dark:bg-red-900/90 border-red-200 dark:border-red-800'
            }`}
          >
            {toast.kind === 'success' ? (
              <div className="w-6 h-6 rounded-full bg-emerald-100 dark:bg-emerald-800 flex items-center justify-center">
                <CheckCircle2 className="w-4 h-4 text-emerald-600 dark:text-emerald-400" />
              </div>
            ) : (
              <div className="w-6 h-6 rounded-full bg-red-100 dark:bg-red-800 flex items-center justify-center">
                <XCircle className="w-4 h-4 text-red-600 dark:text-red-400" />
              </div>
            )}
            <span
              className={`text-sm font-medium ${
                toast.kind === 'success'
                  ? 'text-emerald-800 dark:text-emerald-200'
                  : 'text-red-800 dark:text-red-200'
              }`}
            >
              {toast.message}
            </span>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
