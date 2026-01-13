import { useState, useCallback, useRef, useEffect } from 'react'
import { api, createProgressSocket } from '../api/client'
import { useAppStore } from '../stores/appStore'
import type { QueuedFile, FileStatus } from '../components/FileQueue'
import type { TaggingOptions } from '../components/TaggingOptionsPanel'

interface UseTaggingState {
  files: QueuedFile[]
  isProcessing: boolean
  isPaused: boolean
  currentIndex: number
  taskId: string | null
  error: string | null
  startTime: number | null
}

export function useTagging() {
  const [state, setState] = useState<UseTaggingState>({
    files: [],
    isProcessing: false,
    isPaused: false,
    currentIndex: -1,
    taskId: null,
    error: null,
    startTime: null,
  })

  const wsRef = useRef<{ close: () => void } | null>(null)
  const abortRef = useRef(false)
  const taskIdRef = useRef<string | null>(null)

  // Add files to queue
  const addFiles = useCallback((paths: string[]) => {
    setState((prev) => {
      const existingPaths = new Set(prev.files.map((f) => f.path))
      const newFiles: QueuedFile[] = paths
        .filter((path) => !existingPaths.has(path))
        .map((path) => ({
          path,
          name: path.split('/').pop() || path,
          status: 'pending' as FileStatus,
        }))

      return {
        ...prev,
        files: [...prev.files, ...newFiles],
      }
    })
  }, [])

  // Remove file from queue
  const removeFile = useCallback((path: string) => {
    setState((prev) => ({
      ...prev,
      files: prev.files.filter((f) => f.path !== path),
    }))
  }, [])

  // Clear all files
  const clearFiles = useCallback(() => {
    setState((prev) => ({
      ...prev,
      files: [],
      currentIndex: -1,
    }))
  }, [])

  // Update file status
  const updateFile = useCallback((path: string, updates: Partial<QueuedFile>) => {
    setState((prev) => ({
      ...prev,
      files: prev.files.map((f) =>
        f.path === path ? { ...f, ...updates } : f
      ),
    }))
  }, [])

  // Start batch tagging
  const startTagging = useCallback(async (options: TaggingOptions) => {
    if (state.files.length === 0) return

    // Clean up any existing WebSocket
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }

    abortRef.current = false
    taskIdRef.current = null

    // Capture file paths BEFORE state reset to avoid stale state issues
    const filePaths = state.files.map((f) => f.path)

    // Reset all files to pending
    setState((prev) => ({
      ...prev,
      isProcessing: true,
      isPaused: false,
      currentIndex: 0,
      error: null,
      startTime: Date.now(),
      files: prev.files.map((f) => ({ ...f, status: 'pending' as FileStatus })),
    }))

    try {
      // Start batch task
      const response = await api.tagBatch({
        file_paths: filePaths,
        overwrite: options.overwrite,
        dry_run: false,
        tags_to_write: {
          genre: options.writeGenre,
          album: options.writeAlbum,
          comments: options.writeComments,
          mood: options.writeMood,
          likeness: options.writeLikeness,
        },
        generate_vibes: options.generateVibes,
        generate_hooks: options.detectHooks,
      })

      setState((prev) => ({ ...prev, taskId: response.task_id }))
      taskIdRef.current = response.task_id

      // Connect WebSocket for progress
      wsRef.current = createProgressSocket(response.task_id, (update) => {
        if (update.current_item) {
          // Find the file being processed
          setState((prev) => {
            const itemPath = update.current_item!
            const itemName = itemPath.split(/[/\\]/).pop() || itemPath
            const fileIndex = prev.files.findIndex((f) => {
              // Match by exact path
              if (f.path === itemPath) return true
              // Match by path ending (handles relative vs absolute)
              if (f.path.endsWith(itemPath) || itemPath.endsWith(f.path)) return true
              // Match by filename (extract basename from both)
              if (f.name === itemName) return true
              return false
            })

            if (fileIndex >= 0) {
              const updatedFiles = [...prev.files]
              updatedFiles[fileIndex] = {
                ...updatedFiles[fileIndex],
                status: 'processing',
              }
              return { ...prev, files: updatedFiles, currentIndex: fileIndex }
            }

            if (fileIndex < 0) {
              console.warn('useTagging: Could not match current_item to file:', update.current_item)
            }

            return prev
          })
        }
      })

      // Poll for completion
      const pollInterval = setInterval(async () => {
        if (abortRef.current) {
          clearInterval(pollInterval)
          return
        }

        try {
          const status = await api.getTaskStatus(response.task_id)

          if (status.status === 'completed' || status.status === 'failed') {
            clearInterval(pollInterval)
            wsRef.current?.close()

            // Update files with results
            if (status.result && Array.isArray(status.result)) {
              setState((prev) => {
                const resultMap = new Map(
                  (status.result as Array<{
                    file_path: string
                    status: string
                    tags?: { genre?: string; album?: string; comments?: string }
                    vibe?: string
                    hook?: string
                    error?: string
                  }>).map((r) => [r.file_path, r])
                )

                const updatedFiles = prev.files.map((f) => {
                  const result = resultMap.get(f.path)
                  if (result) {
                    return {
                      ...f,
                      status: (result.status === 'tagged' ? 'tagged' :
                              result.status === 'failed' ? 'failed' :
                              result.status === 'skipped' ? 'skipped' : 'pending') as FileStatus,
                      tags: result.tags,
                      vibe: result.vibe,
                      hook: result.hook,
                      error: result.error,
                    }
                  }
                  return f
                })

                return {
                  ...prev,
                  files: updatedFiles,
                  isProcessing: false,
                  isPaused: false,
                  currentIndex: -1,
                  startTime: null,
                }
              })
            } else {
              setState((prev) => ({
                ...prev,
                isProcessing: false,
                isPaused: false,
                currentIndex: -1,
                startTime: null,
              }))
            }
          }
        } catch (error) {
          // Ignore polling errors
        }
      }, 1000)

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to start tagging'
      setState((prev) => ({
        ...prev,
        isProcessing: false,
        error: errorMessage,
      }))
    }
  }, [state.files])

  // Stop tagging
  const stopTagging = useCallback(async () => {
    abortRef.current = true

    // Cancel the backend task
    if (taskIdRef.current) {
      try {
        await api.cancelTagging(taskIdRef.current)
      } catch (error) {
        // Ignore cancel errors - task may have already completed
        console.warn('Failed to cancel tagging task:', error)
      }
      taskIdRef.current = null
    }

    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }

    setState((prev) => ({
      ...prev,
      isProcessing: false,
      isPaused: false,
      currentIndex: -1,
      taskId: null,
      startTime: null,
    }))
  }, [])

  // Pause tagging
  const pauseTagging = useCallback(async () => {
    if (!taskIdRef.current) return

    try {
      await api.pauseTask(taskIdRef.current)
      setState((prev) => ({ ...prev, isPaused: true }))
    } catch (error) {
      console.warn('Failed to pause tagging task:', error)
    }
  }, [])

  // Resume tagging
  const resumeTagging = useCallback(async () => {
    if (!taskIdRef.current) return

    try {
      await api.resumeTask(taskIdRef.current)
      setState((prev) => ({ ...prev, isPaused: false }))
    } catch (error) {
      console.warn('Failed to resume tagging task:', error)
    }
  }, [])

  // Retry failed file
  const retryFile = useCallback(async (path: string, options: TaggingOptions) => {
    updateFile(path, { status: 'processing', error: undefined })

    try {
      const result = await api.tagFile({
        file_path: path,
        overwrite: options.overwrite,
        dry_run: false,
        tags_to_write: {
          genre: options.writeGenre,
          album: options.writeAlbum,
          comments: options.writeComments,
          mood: options.writeMood,
          likeness: options.writeLikeness,
        },
      })

      updateFile(path, {
        status: result.status as FileStatus,
        tags: result.predicted_tags ? {
          genre: result.predicted_tags.genre || undefined,
          album: result.predicted_tags.album || undefined,
          comments: result.predicted_tags.comments || undefined,
        } : undefined,
        vibe: result.vibe || undefined,
        hook: result.hook || undefined,
        error: result.error || undefined,
      })
    } catch (error) {
      updateFile(path, {
        status: 'failed',
        error: error instanceof Error ? error.message : 'Failed',
      })
    }
  }, [updateFile])

  // Load files from directory
  const loadFromDirectory = useCallback(async (directory: string) => {
    try {
      const result = await api.findMp3s(directory, true)
      const paths = result.files.map((f) => f.path)
      addFiles(paths)
      return paths.length
    } catch (error) {
      throw error
    }
  }, [addFiles])

  // Update tagging stats when state changes
  useEffect(() => {
    const { setTaggingStats, clearTaggingStats } = useAppStore.getState()

    if (state.files.length === 0) {
      clearTaggingStats()
      return
    }

    const completed = state.files.filter(f => ['tagged', 'failed', 'skipped'].includes(f.status)).length
    const pending = state.files.filter(f => f.status === 'pending').length
    const processing = state.files.filter(f => f.status === 'processing').length
    const failed = state.files.filter(f => f.status === 'failed').length

    const elapsed = state.startTime ? (Date.now() - state.startTime) / 1000 : 0
    const avgTime = completed > 0 ? elapsed / completed : 0
    const eta = avgTime * (pending + processing)

    setTaggingStats({
      total: state.files.length,
      completed,
      pending,
      processing,
      failed,
      startTime: state.startTime,
      avgTimePerFile: avgTime,
      eta,
    })
  }, [state.files, state.startTime])

  return {
    // State
    files: state.files,
    isProcessing: state.isProcessing,
    isPaused: state.isPaused,
    currentIndex: state.currentIndex,
    error: state.error,
    startTime: state.startTime,

    // Actions
    addFiles,
    removeFile,
    clearFiles,
    startTagging,
    stopTagging,
    pauseTagging,
    resumeTagging,
    retryFile,
    loadFromDirectory,
  }
}
