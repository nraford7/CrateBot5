import { useState, useCallback, useEffect, useRef } from 'react'
import { api, createProgressSocket } from '../api/client'
import { useAppStore } from '../stores/appStore'

interface SelectedTags {
  genre: string[]
  timing: string[]
  mood: string[]
  descriptive: string[]
}

interface DiscoveredTags {
  genre: { values: Record<string, number> }
  timing: { values: Record<string, number> }
  mood: { values: Record<string, number> }
  descriptive: { values: Record<string, number> }
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
    timingAccuracy?: number
    moodAccuracy?: number
    descriptiveF1?: number
  } | null
  error: string | null
  logs: string[]
  startTime: number | null
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
    startTime: null,
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
  const scanDirectory = useCallback(async (
    directory: string,
    tagSources?: { genre_frame?: string; timing_frame?: string; mood_frame?: string; comments_frame?: string }
  ) => {
    setDiscoveredTags({ data: null, isLoading: true, error: null })
    addLog(`Scanning directory: ${directory}`)

    try {
      const result = await api.scanTags(directory, tagSources)
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
    modelName: string = 'cratebot',
    tagSources?: { genre_frame?: string; timing_frame?: string; mood_frame?: string; comments_frame?: string }
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
      startTime: Date.now(),
    }))

    addLog('Starting training...')
    addLog(`Genre tags: ${selectedTags.genre.length}`)
    addLog(`Timing tags: ${selectedTags.timing.length}`)
    addLog(`Mood tags: ${selectedTags.mood.length}`)
    addLog(`Descriptive tags: ${selectedTags.descriptive.length}`)

    try {
      const modelPath = `~/.cratebot/models/${modelName}.pkl`

      const response = await api.startTraining({
        training_dir: trainingDir,
        output_model_path: modelPath,
        selected_tags: selectedTags,
        test_size: 0.2,
        tag_sources: tagSources,
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

            const result = status.result as { metrics?: Record<string, any> } | undefined
            const rawMetrics = result?.metrics
            const parsedMetrics: TrainingState['metrics'] | null = rawMetrics && typeof rawMetrics === 'object'
              ? {
                  genreAccuracy: rawMetrics.genre?.accuracy,
                  timingAccuracy: rawMetrics.timing?.accuracy ?? rawMetrics.album?.accuracy,
                  moodAccuracy: rawMetrics.mood?.accuracy,
                  descriptiveF1: rawMetrics.descriptive?.avg_f1 ?? rawMetrics.comments?.avg_f1,
                }
              : null
            const hasMetrics = parsedMetrics
              ? Object.values(parsedMetrics).some((value) => typeof value === 'number')
              : false

            setState((prev) => ({
              ...prev,
              status: 'completed',
              phase: 'complete',
              progress: 100,
              metrics: hasMetrics ? parsedMetrics : null,
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

  // Pause training
  const pauseTraining = useCallback(async () => {
    if (!state.taskId) return
    addLog('Pausing training...')
    try {
      await api.pauseTask(state.taskId)
      setState((prev) => ({ ...prev, status: 'paused' }))
      addLog('Training paused')
    } catch (error) {
      addLog(`Failed to pause: ${error}`)
    }
  }, [state.taskId, addLog])

  // Resume training
  const resumeTraining = useCallback(async () => {
    if (!state.taskId) return
    addLog('Resuming training...')
    try {
      await api.resumeTask(state.taskId)
      setState((prev) => ({ ...prev, status: 'running' }))
      addLog('Training resumed')
    } catch (error) {
      addLog(`Failed to resume: ${error}`)
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
      startTime: null,
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
    pauseTraining,
    resumeTraining,
    clearLogs,
    reset,
  }
}
