import { useState, useCallback, ReactNode } from 'react'
import { Upload } from 'lucide-react'
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
        'relative transition-colors',
        isDragging && !disabled && 'ring-2 ring-accent ring-offset-2 rounded-xl',
        className
      )}
    >
      {children}

      {/* Drag Overlay */}
      {isDragging && !disabled && (
        <div className="absolute inset-0 bg-accent/10 backdrop-blur-sm rounded-xl flex items-center justify-center z-10">
          <div className="text-center">
            <Upload className="w-12 h-12 text-accent mx-auto mb-2" />
            <p className="text-lg font-medium text-accent">Drop MP3 files here</p>
          </div>
        </div>
      )}
    </div>
  )
}
