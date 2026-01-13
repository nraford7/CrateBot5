import { useRef, useEffect } from 'react'
import { Terminal, Copy, Trash2 } from 'lucide-react'

interface TrainingConsoleProps {
  logs: string[]
  onClear?: () => void
}

export function TrainingConsole({ logs, onClear }: TrainingConsoleProps) {
  const scrollRef = useRef<HTMLDivElement>(null)

  // Auto-scroll to bottom when new logs arrive
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [logs])

  const handleCopy = () => {
    navigator.clipboard.writeText(logs.join('\n'))
  }

  return (
    <div className="card p-0 overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-2 bg-gray-50 dark:bg-gray-800 border-b border-border dark:border-border-dark">
        <div className="flex items-center gap-2 text-sm text-muted">
          <Terminal className="w-4 h-4" />
          <span>Console</span>
        </div>
        <div className="flex gap-1">
          <button
            onClick={handleCopy}
            className="p-1.5 hover:bg-gray-200 dark:hover:bg-gray-700 rounded"
            title="Copy logs"
          >
            <Copy className="w-3.5 h-3.5 text-muted" />
          </button>
          {onClear && (
            <button
              onClick={onClear}
              className="p-1.5 hover:bg-gray-200 dark:hover:bg-gray-700 rounded"
              title="Clear logs"
            >
              <Trash2 className="w-3.5 h-3.5 text-muted" />
            </button>
          )}
        </div>
      </div>

      {/* Log Output */}
      <div
        ref={scrollRef}
        className="h-48 overflow-auto bg-gray-900 p-3 font-mono text-xs"
      >
        {logs.length === 0 ? (
          <div className="text-gray-500 italic">No output yet...</div>
        ) : (
          logs.map((log, index) => {
            // Parse timestamp if present
            const match = log.match(/^\[([^\]]+)\]\s*(.*)$/)
            const timestamp = match ? match[1] : null
            const message = match ? match[2] : log

            // Color code based on content
            let textColor = 'text-gray-300'
            if (message.toLowerCase().includes('error')) {
              textColor = 'text-red-400'
            } else if (message.toLowerCase().includes('warning')) {
              textColor = 'text-amber-400'
            } else if (message.toLowerCase().includes('complete') || message.toLowerCase().includes('success')) {
              textColor = 'text-green-400'
            } else if (message.includes('%')) {
              textColor = 'text-blue-400'
            }

            return (
              <div key={index} className="leading-relaxed">
                {timestamp && (
                  <span className="text-gray-600">[{timestamp}] </span>
                )}
                <span className={textColor}>{message}</span>
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
