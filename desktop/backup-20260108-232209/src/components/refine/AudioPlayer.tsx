/**
 * AudioPlayer Component
 * Waveform visualization and playback controls using wavesurfer.js
 */
import { useRef, useEffect, useState, useCallback } from 'react'
import { Play, Pause, SkipBack, SkipForward } from 'lucide-react'
import WaveSurfer from 'wavesurfer.js'

interface AudioPlayerProps {
  filePath: string | null
  onPrev?: () => void
  onNext?: () => void
  hasPrev?: boolean
  hasNext?: boolean
}

function formatTime(seconds: number): string {
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

export function AudioPlayer({
  filePath,
  onPrev,
  onNext,
  hasPrev = true,
  hasNext = true,
}: AudioPlayerProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const wavesurferRef = useRef<WaveSurfer | null>(null)
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [duration, setDuration] = useState(0)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Initialize wavesurfer
  useEffect(() => {
    if (!containerRef.current) return

    const ws = WaveSurfer.create({
      container: containerRef.current,
      waveColor: '#94a3b8', // slate-400
      progressColor: '#3b82f6', // blue-500
      cursorColor: '#1d4ed8', // blue-700
      barWidth: 2,
      barGap: 1,
      barRadius: 2,
      height: 48,
      normalize: true,
      backend: 'WebAudio',
    })

    ws.on('play', () => setIsPlaying(true))
    ws.on('pause', () => setIsPlaying(false))
    ws.on('finish', () => setIsPlaying(false))
    ws.on('ready', () => {
      setDuration(ws.getDuration())
      setIsLoading(false)
      setError(null)
    })
    ws.on('timeupdate', (time) => setCurrentTime(time))
    ws.on('error', (err) => {
      console.error('WaveSurfer error:', err)
      setError('Failed to load audio')
      setIsLoading(false)
    })

    wavesurferRef.current = ws

    return () => {
      ws.destroy()
    }
  }, [])

  // Load new file when filePath changes
  useEffect(() => {
    const ws = wavesurferRef.current
    if (!ws) return

    // Reset state
    setIsPlaying(false)
    setCurrentTime(0)
    setDuration(0)
    setError(null)

    if (!filePath) return

    setIsLoading(true)

    // Convert file path to cratebot:// URL for secure local file access
    // The cratebot:// protocol is registered in the Electron main process
    const fileUrl = filePath.startsWith('cratebot://') ? filePath : `cratebot://${filePath}`

    ws.load(fileUrl)
  }, [filePath])

  const togglePlayPause = useCallback(() => {
    const ws = wavesurferRef.current
    if (!ws) return
    ws.playPause()
  }, [])

  const handlePrev = useCallback(() => {
    const ws = wavesurferRef.current
    if (ws) {
      ws.pause()
      setIsPlaying(false)
    }
    onPrev?.()
  }, [onPrev])

  const handleNext = useCallback(() => {
    const ws = wavesurferRef.current
    if (ws) {
      ws.pause()
      setIsPlaying(false)
    }
    onNext?.()
  }, [onNext])

  if (!filePath) {
    return (
      <div className="p-4 border-b border-border dark:border-border-dark">
        <div className="h-12 bg-gray-100 dark:bg-gray-800 rounded-lg flex items-center justify-center text-sm text-muted">
          No track selected
        </div>
      </div>
    )
  }

  return (
    <div className="p-4 border-b border-border dark:border-border-dark">
      <div className="flex items-center gap-4">
        {/* Transport Controls */}
        <button
          onClick={handlePrev}
          disabled={!hasPrev}
          className="btn btn-ghost p-2 disabled:opacity-30"
        >
          <SkipBack className="w-5 h-5" />
        </button>

        <button
          onClick={togglePlayPause}
          disabled={isLoading || !!error}
          className="btn btn-primary p-3 rounded-full disabled:opacity-50"
        >
          {isPlaying ? (
            <Pause className="w-5 h-5" />
          ) : (
            <Play className="w-5 h-5" />
          )}
        </button>

        <button
          onClick={handleNext}
          disabled={!hasNext}
          className="btn btn-ghost p-2 disabled:opacity-30"
        >
          <SkipForward className="w-5 h-5" />
        </button>

        {/* Waveform */}
        <div className="flex-1 relative">
          {isLoading && (
            <div className="absolute inset-0 flex items-center justify-center bg-gray-100 dark:bg-gray-800 rounded-lg z-10">
              <span className="text-sm text-muted">Loading...</span>
            </div>
          )}
          {error && (
            <div className="absolute inset-0 flex items-center justify-center bg-red-50 dark:bg-red-900/20 rounded-lg z-10">
              <span className="text-sm text-red-600 dark:text-red-400">{error}</span>
            </div>
          )}
          <div
            ref={containerRef}
            className="h-12 rounded-lg overflow-hidden bg-gray-100 dark:bg-gray-800"
          />
        </div>

        {/* Time Display */}
        <div className="text-sm font-mono text-muted min-w-[80px] text-right">
          {formatTime(currentTime)} / {formatTime(duration)}
        </div>
      </div>
    </div>
  )
}
