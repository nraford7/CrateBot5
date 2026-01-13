import { Wifi, WifiOff, Loader2, CheckCircle2, XCircle } from 'lucide-react'
import { useAppStore } from '../stores/appStore'
import { clsx } from 'clsx'

export function StatusBar() {
  const { serverStatus, model, currentTask } = useAppStore()
  const buildStamp = __BUILD_STAMP__
  const buildLabel = new Date(buildStamp).toLocaleString()

  return (
    <footer className="h-8 bg-sidebar dark:bg-sidebar-dark border-t border-border dark:border-border-dark flex items-center px-4 text-xs">
      {/* Server Status */}
      <div className="flex items-center gap-2">
        {serverStatus === 'connected' ? (
          <Wifi className="w-3.5 h-3.5 text-green-500" />
        ) : serverStatus === 'connecting' ? (
          <Loader2 className="w-3.5 h-3.5 text-yellow-500 animate-spin" />
        ) : (
          <WifiOff className="w-3.5 h-3.5 text-red-500" />
        )}
        <span className={clsx(
          serverStatus === 'connected' ? 'text-green-600 dark:text-green-400' :
          serverStatus === 'connecting' ? 'text-yellow-600 dark:text-yellow-400' :
          'text-red-600 dark:text-red-400'
        )}>
          {serverStatus === 'connected' ? 'Connected' :
           serverStatus === 'connecting' ? 'Connecting...' :
           'Disconnected'}
        </span>
      </div>

      {/* Separator */}
      <div className="w-px h-4 bg-border dark:bg-border-dark mx-4" />

      {/* Model Status */}
      <div className="flex items-center gap-2">
        {model.loaded ? (
          <CheckCircle2 className="w-3.5 h-3.5 text-green-500" />
        ) : (
          <XCircle className="w-3.5 h-3.5 text-muted" />
        )}
        <span className="text-muted">
          {model.loaded ? `Model: ${model.name || 'Loaded'}` : 'No model loaded'}
        </span>
      </div>

      {/* Spacer */}
      <div className="flex-1" />

      {/* Build Stamp */}
      <div className="text-muted mr-4">
        Build: {buildLabel}
      </div>

      {/* Current Task Progress */}
      {currentTask && (
        <div className="flex items-center gap-2">
          <Loader2 className="w-3.5 h-3.5 text-accent animate-spin" />
          <span className="text-muted">
            {currentTask.type}: {currentTask.progress.toFixed(0)}%
          </span>
          {currentTask.message && (
            <span className="text-muted truncate max-w-48">
              - {currentTask.message}
            </span>
          )}
        </div>
      )}
    </footer>
  )
}
