/**
 * TrainingConsole Component - Redesigned
 * Console output for training logs
 */
import { useRef, useEffect } from 'react'
import { Terminal, Copy, Trash2, Check } from 'lucide-react'
import { motion } from 'framer-motion'
import { useState } from 'react'

interface TrainingConsoleProps {
  logs: string[]
  onClear?: () => void
}

export function TrainingConsole({ logs, onClear }: TrainingConsoleProps) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const [copied, setCopied] = useState(false)

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [logs])

  const handleCopy = async () => {
    await navigator.clipboard.writeText(logs.join('\n'))
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="card p-0 overflow-hidden"
    >
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 bg-surface-sunken dark:bg-surface-dark-sunken border-b border-border-light dark:border-border-dark">
        <div className="flex items-center gap-2 text-sm text-stone-600 dark:text-stone-400">
          <Terminal className="w-4 h-4" />
          <span className="font-medium">Console</span>
          <span className="text-xs text-stone-400 dark:text-stone-500">
            {logs.length} lines
          </span>
        </div>
        <div className="flex gap-1">
          <motion.button
            onClick={handleCopy}
            whileHover={{ scale: 1.1 }}
            whileTap={{ scale: 0.9 }}
            className="p-1.5 hover:bg-surface-light dark:hover:bg-surface-dark rounded-lg transition-colors"
            title="Copy logs"
          >
            {copied ? (
              <Check className="w-3.5 h-3.5 text-emerald-500" />
            ) : (
              <Copy className="w-3.5 h-3.5 text-stone-400" />
            )}
          </motion.button>
          {onClear && (
            <motion.button
              onClick={onClear}
              whileHover={{ scale: 1.1 }}
              whileTap={{ scale: 0.9 }}
              className="p-1.5 hover:bg-surface-light dark:hover:bg-surface-dark rounded-lg transition-colors"
              title="Clear logs"
            >
              <Trash2 className="w-3.5 h-3.5 text-stone-400" />
            </motion.button>
          )}
        </div>
      </div>

      {/* Log Output */}
      <div
        ref={scrollRef}
        className="h-48 overflow-auto bg-stone-900 dark:bg-stone-950 p-4 font-mono text-xs leading-relaxed"
      >
        {logs.length === 0 ? (
          <div className="text-stone-600 italic flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-stone-700 animate-pulse" />
            Waiting for output...
          </div>
        ) : (
          logs.map((log, index) => {
            // Parse timestamp if present
            const match = log.match(/^\[([^\]]+)\]\s*(.*)$/)
            const timestamp = match ? match[1] : null
            const message = match ? match[2] : log

            // Color code based on content
            let textColor = 'text-stone-300'
            if (message.toLowerCase().includes('error')) {
              textColor = 'text-red-400'
            } else if (message.toLowerCase().includes('warning')) {
              textColor = 'text-amber-400'
            } else if (message.toLowerCase().includes('complete') || message.toLowerCase().includes('success')) {
              textColor = 'text-emerald-400'
            } else if (message.includes('%')) {
              textColor = 'text-amber-300'
            }

            return (
              <motion.div
                key={index}
                initial={{ opacity: 0, x: -10 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ duration: 0.2 }}
                className="py-0.5"
              >
                {timestamp && (
                  <span className="text-stone-600 mr-2">[{timestamp}]</span>
                )}
                <span className={textColor}>{message}</span>
              </motion.div>
            )
          })
        )}
      </div>
    </motion.div>
  )
}
