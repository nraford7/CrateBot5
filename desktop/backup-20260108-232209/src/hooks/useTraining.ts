import { useState, useCallback, useEffect, useRef } from 'react'
import { api, createProgressSocket } from '../api/client'
import { useAppStore } from '../stores/appStore'

interface SelectedTags {
  genre: string[]
  album: string[]
  comments: string[]
}

interface DiscoveredTags {
  genre: { values: Record<string, number> }
  album: { values: Record<string, number> }
  comments: { values: Record<string, number> }
  total_files: number
}

interface TrainingState {
  status: 'idle' | 'scanning' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled'
  taskId: string | null
  phase: string
  progress: number
  currentFile: string | null
  filesProcessed: number
  totalFiles: number
  samplesCollected: number
  metrics: {
    genreAccuracy?: number
    albumAccuracy?: number
    commentsF1?: number
  } | null
  error: string | null
  logs: string[]
}

interface DiscoveredTagsState {
  data: DiscoveredTags | null
  isLoading: boolean
  error: string | null
}

export function useTraining() {
  const { loadModelInfo } = useAppStore()

  const [state, setState] = useState<TrainingState>({
    status: 'idle',
    taskId: null,
    phase: 'idle',
    progress: 0,
    currentFile: null,
    filesProcessed: 0,
    totalFiles: 0,
    samplesCollected: 0,
    metrics: null,
    error: null,
    logs: [],
  })

  const [discoveredTags, setDiscoveredTags] = useState<DiscoveredTagsState>({
    data: null,
    isLoading: false,
    error: null,
  })

  const wsRef = useRef<{ close: () => void } | null>(null)

  // Add log message
  const addLog = useCallback((message: string) => {
    const timestamp = new Date().toISOString().slice(11, 19)
    setState((prev) => ({
      ...prev,
      logs: [...prev.logs, `[${timestamp}] ${message}`],
    }))
  }, [])

  // Clear logs
  const clearLogs = useCallback(() => {
    setState((prev) => ({ ...prev, logs: [] }))
  }, [])

  // Scan directory for tags
  const scanDirectory = useCallback(async (directory: string) => {
    setDiscoveredTags({ data: null, isLoading: true, error: null })
    addLog(`Scanning directory: ${directory}`)

    try {
      const result = await api.scanTags(directory)
      setDiscoveredTags({
        data: result as DiscoveredTags,
        isLoading: false,
        error: null,
      })
      addLog(`Found ${(result as DiscoveredTags).total_files} files with tags`)
      return result as DiscoveredTags
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to scan directory'
      setDiscoveredTags({
        data: null,
        isLoading: false,
        error: errorMessage,
      })
      addLog(`Error scanning: ${errorMessage}`)
      throw error
    }
  }, [addLog])

  // Start training
  const startTraining = useCallback(async (
    trainingDir: string,
    selectedTags: SelectedTags,
    modelName: string = 'cratebot'
  ) => {
    // Clean up any existing WebSocket
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }

    setState((prev) => ({
      ...prev,
      status: 'running',
      phase: 'collecting',
      progress: 0,
      error: null,
      metrics: null,
    }))

    addLog('Starting training...')
    addLog(`Genre tags: ${selectedTags.genre.length}`)
    addLog(`Album tags: ${selectedTags.album.length}`)
    addLog(`Comment tags: ${selectedTags.comments.length}`)

    try {
      const modelPath = `~/.cratebot/models/${modelName}.pkl`

      const response = await api.startTraining({
        training_dir: trainingDir,
        output_model_path: modelPath,
        selected_tags: selectedTags,
        test_size: 0.2,
      })

      const taskId = response.task_id
      setState((prev) => ({ ...prev, taskId }))
      addLog(`Training task started: ${taskId}`)

      // Connect WebSocket for progress updates
      wsRef.current = createProgressSocket(taskId, (update) => {
        setState((prev) => ({
          ...prev,
          phase: update.phase || prev.phase,
          progress: update.progress,
          currentFile: update.current_item || prev.currentFile,
          filesProcessed: update.current_index,
          totalFiles: update.total_items,
          status: update.status === 'completed' ? 'completed' :
                  update.status === 'failed' ? 'failed' :
                  update.status === 'cancelled' ? 'cancelled' :
                  update.status === 'paused' ? 'paused' : 'running',
        }))

        if (update.message) {
          addLog(update.message)
        }
      })

      // Poll for completion
      const pollInterval = setInterval(async () => {
        try {
          const status = await api.getTaskStatus(taskId)

          if (status.status === 'completed') {
            clearInterval(pollInterval)
            wsRef.current?.close()

            const result = status.result as { metrics?: TrainingState['metrics'] } | undefined

            setState((prev) => ({
              ...prev,
              status: 'completed',
              phase: 'complete',
              progress: 100,
              metrics: result?.metrics || null,
            }))

            addLog('Training completed successfully!')

            // Reload model info
            await loadModelInfo()
          } else if (status.status === 'failed') {
            clearInterval(pollInterval)
            wsRef.current?.close()

            setState((prev) => ({
              ...prev,
              status: 'failed',
              error: status.error || 'Training failed',
            }))

            addLog(`Training failed: ${status.error}`)
          } else if (status.status === 'cancelled') {
            clearInterval(pollInterval)
            wsRef.current?.close()

            setState((prev) => ({
              ...prev,
              status: 'cancelled',
            }))

            addLog('Training cancelled')
          }
        } catch (error) {
          // Ignore polling errors, WebSocket will handle updates
        }
      }, 2000)

      return taskId
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to start training'
      setState((prev) => ({
        ...prev,
        status: 'failed',
        error: errorMessage,
      }))
      addLog(`Error: ${errorMessage}`)
      throw error
    }
  }, [addLog, loadModelInfo])

  // Cancel training
  const cancelTraining = useCallback(async () => {
    if (!state.taskId) return

    addLog('Cancelling training...')
    try {
      await api.cancelTraining(state.taskId)
      setState((prev) => ({ ...prev, status: 'cancelled' }))
      addLog('Training cancelled')
    } catch (error) {
      addLog(`Failed to cancel: ${error}`)
    }
  }, [state.taskId, addLog])

  // Reset state
  const reset = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }

    setState({
      status: 'idle',
      taskId: null,
      phase: 'idle',
      progress: 0,
      currentFile: null,
      filesProcessed: 0,
      totalFiles: 0,
      samplesCollected: 0,
      metrics: null,
      error: null,
      logs: [],
    })

    setDiscoveredTags({
      data: null,
      isLoading: false,
      error: null,
    })
  }, [])

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (wsRef.current) {
        wsRef.current.close()
      }
    }
  }, [])

  return {
    // State
    ...state,
    discoveredTags: discoveredTags.data,
    isScanning: discoveredTags.isLoading,
    scanError: discoveredTags.error,

    // Actions
    scanDirectory,
    startTraining,
    cancelTraining,
    clearLogs,
    reset,
  }
}
