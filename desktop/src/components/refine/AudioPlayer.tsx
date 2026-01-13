/**
 * AudioPlayer Component - Redesigned
 * Waveform visualization with branded styling
 */
import { useRef, useEffect, useState, useCallback } from 'react'
import { Play, Pause, SkipBack, SkipForward, Volume2 } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import WaveSurfer from 'wavesurfer.js'
import { clsx } from 'clsx'

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

  useEffect(() => {
    if (!containerRef.current) return

    const ws = WaveSurfer.create({
      container: containerRef.current,
      waveColor: '#d6d3d1',
      progressColor: '#f59e0b',
      cursorColor: '#d97706',
      barWidth: 3,
      barGap: 2,
      barRadius: 3,
      height: 64,
      normalize: true,
      backend: 'WebAudio',
      cursorWidth: 2,
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

  useEffect(() => {
    const ws = wavesurferRef.current
    if (!ws) return

    setIsPlaying(false)
    setCurrentTime(0)
    setDuration(0)
    setError(null)

    if (!filePath) return

    setIsLoading(true)
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
      <div className="audio-player">
        <div className="flex items-center justify-center h-20 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
          <div className="text-center">
            <Volume2 className="w-6 h-6 mx-auto mb-2 text-stone-400 opacity-40" />
            <p className="text-sm text-stone-400">No track selected</p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <motion.div
      className="audio-player"
      initial={{ opacity: 0, y: -10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
    >
      <div className="flex items-center gap-5">
        {/* Transport Controls */}
        <div className="flex items-center gap-2">
          <motion.button
            onClick={handlePrev}
            disabled={!hasPrev}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className={clsx(
              'audio-transport-btn',
              !hasPrev && 'opacity-30 cursor-not-allowed'
            )}
          >
            <SkipBack className="w-5 h-5 text-stone-600 dark:text-stone-400" />
          </motion.button>

          <motion.button
            onClick={togglePlayPause}
            disabled={isLoading || !!error}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.92 }}
            className={clsx(
              'audio-play-btn',
              isPlaying && 'playing',
              (isLoading || error) && 'opacity-50 cursor-not-allowed'
            )}
          >
            <AnimatePresence mode="wait">
              {isPlaying ? (
                <motion.div
                  key="pause"
                  initial={{ scale: 0, rotate: -90 }}
                  animate={{ scale: 1, rotate: 0 }}
                  exit={{ scale: 0, rotate: 90 }}
                  transition={{ duration: 0.15 }}
                >
                  <Pause className="w-6 h-6" />
                </motion.div>
              ) : (
                <motion.div
                  key="play"
                  initial={{ scale: 0, rotate: 90 }}
                  animate={{ scale: 1, rotate: 0 }}
                  exit={{ scale: 0, rotate: -90 }}
                  transition={{ duration: 0.15 }}
                >
                  <Play className="w-6 h-6 ml-0.5" />
                </motion.div>
              )}
            </AnimatePresence>
          </motion.button>

          <motion.button
            onClick={handleNext}
            disabled={!hasNext}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className={clsx(
              'audio-transport-btn',
              !hasNext && 'opacity-30 cursor-not-allowed'
            )}
          >
            <SkipForward className="w-5 h-5 text-stone-600 dark:text-stone-400" />
          </motion.button>
        </div>

        {/* Waveform Container */}
        <div className="flex-1 relative">
          <AnimatePresence>
            {isLoading && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="absolute inset-0 flex items-center justify-center bg-surface-sunken dark:bg-surface-dark-sunken rounded-xl z-10"
              >
                <div className="flex items-center gap-2 text-stone-500">
                  <motion.div
                    animate={{ rotate: 360 }}
                    transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                  >
                    <Volume2 className="w-5 h-5" />
                  </motion.div>
                  <span className="text-sm">Loading...</span>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          <AnimatePresence>
            {error && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="absolute inset-0 flex items-center justify-center bg-red-50 dark:bg-red-900/20 rounded-xl z-10"
              >
                <span className="text-sm text-red-600 dark:text-red-400">{error}</span>
              </motion.div>
            )}
          </AnimatePresence>

          <div
            ref={containerRef}
            className="audio-waveform"
          />
        </div>

        {/* Time Display */}
        <div className="flex flex-col items-end min-w-[90px]">
          <span className="audio-time text-stone-700 dark:text-stone-300 font-medium">
            {formatTime(currentTime)}
          </span>
          <span className="audio-time text-stone-400 dark:text-stone-500 text-xs">
            / {formatTime(duration)}
          </span>
        </div>
      </div>
    </motion.div>
  )
}
