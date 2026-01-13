import { motion, AnimatePresence } from 'framer-motion'
import { CheckCircle2, Edit3, X } from 'lucide-react'

interface CompletionDialogProps {
  isOpen: boolean
  onClose: () => void
  onReview: () => void
  taggedCount: number
  failedCount: number
}

export function CompletionDialog({
  isOpen,
  onClose,
  onReview,
  taggedCount,
  failedCount,
}: CompletionDialogProps) {
  return (
    <AnimatePresence>
      {isOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="modal-backdrop"
            onClick={onClose}
          />

          {/* Dialog */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.95 }}
            className="fixed inset-0 z-50 flex items-center justify-center p-4"
          >
            <div className="modal w-full max-w-md p-6 relative">
              {/* Close button */}
              <button
                onClick={onClose}
                className="absolute top-4 right-4 p-1.5 rounded-lg text-stone-400 hover:text-stone-600 dark:hover:text-stone-300 hover:bg-surface-sunken dark:hover:bg-surface-dark-sunken transition-colors"
              >
                <X className="w-5 h-5" />
              </button>

              {/* Content */}
              <div className="text-center">
                <div className="w-16 h-16 mx-auto rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center mb-4">
                  <CheckCircle2 className="w-8 h-8 text-emerald-600 dark:text-emerald-400" />
                </div>

                <h2 className="font-display text-xl font-semibold text-stone-900 dark:text-stone-100 mb-2">
                  Tagging Complete!
                </h2>

                <p className="text-stone-500 dark:text-stone-400 mb-6">
                  {taggedCount} {taggedCount === 1 ? 'file' : 'files'} tagged successfully
                  {failedCount > 0 && `, ${failedCount} failed`}.
                </p>

                <p className="text-sm text-stone-600 dark:text-stone-400 mb-6">
                  Would you like to review what was written and make any changes?
                </p>

                {/* Actions */}
                <div className="flex gap-3">
                  <button
                    onClick={onClose}
                    className="btn btn-secondary flex-1"
                  >
                    Done
                  </button>
                  <button
                    onClick={onReview}
                    className="btn btn-primary flex-1"
                  >
                    <Edit3 className="w-4 h-4" />
                    Review Tags
                  </button>
                </div>
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  )
}
