/**
 * DropZone Component - Redesigned
 * Drag and drop zone for file uploads
 */
import { useState, useCallback, ReactNode } from 'react'
import { Upload } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'

interface DropZoneProps {
  onDrop: (paths: string[]) => void
  accept?: string[]
  children: ReactNode
  disabled?: boolean
  className?: string
}

export function DropZone({
  onDrop,
  accept = ['.mp3'],
  children,
  disabled = false,
  className,
}: DropZoneProps) {
  const [isDragging, setIsDragging] = useState(false)

  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    if (!disabled) {
      setIsDragging(true)
    }
  }, [disabled])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setIsDragging(false)
  }, [])

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
    setIsDragging(false)

    if (disabled) return

    const files = Array.from(e.dataTransfer.files)

    // Filter by accepted extensions
    const validFiles = files.filter((file) => {
      const ext = '.' + file.name.split('.').pop()?.toLowerCase()
      return accept.includes(ext)
    })

    if (validFiles.length > 0) {
      // In Electron, we can get the file paths
      // In browser, we'd need to handle differently
      const paths = validFiles.map((file) => {
        // @ts-ignore - path is available in Electron
        return file.path || file.name
      })
      onDrop(paths)
    }
  }, [disabled, accept, onDrop])

  return (
    <div
      onDragEnter={handleDragEnter}
      onDragLeave={handleDragLeave}
      onDragOver={handleDragOver}
      onDrop={handleDrop}
      className={clsx(
        'relative transition-all duration-300',
        isDragging && !disabled && 'ring-2 ring-amber-500 ring-offset-4 ring-offset-surface-light dark:ring-offset-surface-dark rounded-2xl',
        className
      )}
    >
      {children}

      {/* Drag Overlay */}
      <AnimatePresence>
        {isDragging && !disabled && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="absolute inset-0 bg-amber-500/10 backdrop-blur-sm rounded-2xl flex items-center justify-center z-10"
          >
            <motion.div
              initial={{ scale: 0.9, y: 10 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.9, y: 10 }}
              className="text-center"
            >
              <motion.div
                animate={{ y: [0, -8, 0] }}
                transition={{ duration: 1.5, repeat: Infinity, ease: 'easeInOut' }}
              >
                <Upload className="w-14 h-14 text-amber-500 mx-auto mb-3" />
              </motion.div>
              <p className="text-lg font-display font-semibold text-amber-600 dark:text-amber-400">
                Drop MP3 files here
              </p>
              <p className="text-sm text-amber-500/70 mt-1">
                Release to add files to queue
              </p>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}
