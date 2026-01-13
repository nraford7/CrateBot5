/**
 * CrateBot3 - Redesigned AudioPlayer
 * "Vinyl Warmth" Design System
 *
 * This is THE signature component of CrateBot.
 * It needs to feel like a premium audio tool.
 *
 * Key changes:
 * - Larger, more prominent waveform
 * - Glowing play button with brand colors
 * - Branded waveform colors (amber progress)
 * - Smooth animations and hover states
 * - Time display with mono font
 * - Track name display
 */

import { useRef, useEffect, useState, useCallback } from 'react'
import { Play, Pause, SkipBack, SkipForward, Volume2 } from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import WaveSurfer from 'wavesurfer.js'
import { clsx } from 'clsx'

interface AudioPlayerProps {
  filePath: string | null
  trackName?: string
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
  trackName,
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
  const [isHovering, setIsHovering] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Waveform configuration with brand colors
  useEffect(() => {
    if (!containerRef.current) return

    const ws = WaveSurfer.create({
      container: containerRef.current,
      // Waveform colors - brand aligned
      waveColor: '#d6d3d1', // stone-300 (base)
      progressColor: '#f59e0b', // amber-500 (progress)
      cursorColor: '#d97706', // amber-600 (cursor)
      // Styling
      barWidth: 3,
      barGap: 2,
      barRadius: 3,
      height: 64,
      normalize: true,
      backend: 'WebAudio',
      // Cursor style
      cursorWidth: 2,
    })

    // Event handlers
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

    return () => ws.destroy()
  }, [])

  // Load file
  useEffect(() => {
    const ws = wavesurferRef.current
    if (!ws) return

    setIsPlaying(false)
    setCurrentTime(0)
    setDuration(0)
    setError(null)

    if (!filePath) return

    setIsLoading(true)
    const fileUrl = filePath.startsWith('cratebot://')
      ? filePath
      : `cratebot://${filePath}`
    ws.load(fileUrl)
  }, [filePath])

  const togglePlayPause = useCallback(() => {
    wavesurferRef.current?.playPause()
  }, [])

  const handlePrev = useCallback(() => {
    wavesurferRef.current?.pause()
    setIsPlaying(false)
    onPrev?.()
  }, [onPrev])

  const handleNext = useCallback(() => {
    wavesurferRef.current?.pause()
    setIsPlaying(false)
    onNext?.()
  }, [onNext])

  // Empty state
  if (!filePath) {
    return (
      <div className="audio-player">
        <div className="flex items-center justify-center h-24 rounded-xl bg-surface-sunken dark:bg-surface-dark-sunken">
          <div className="text-center">
            <Volume2 className="w-8 h-8 mx-auto mb-2 text-text-muted opacity-40" />
            <p className="text-body-sm text-text-muted">No track selected</p>
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
      onMouseEnter={() => setIsHovering(true)}
      onMouseLeave={() => setIsHovering(false)}
    >
      {/* Track Info (above controls) */}
      {trackName && (
        <motion.div
          className="mb-4 px-1"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.1 }}
        >
          <h3 className="font-display font-semibold text-heading-md text-text-primary truncate">
            {trackName}
          </h3>
        </motion.div>
      )}

      <div className="flex items-center gap-5">
        {/* Transport Controls */}
        <div className="flex items-center gap-2">
          {/* Previous */}
          <motion.button
            onClick={handlePrev}
            disabled={!hasPrev}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className={clsx(
              'audio-transport-btn p-2.5',
              !hasPrev && 'opacity-30 cursor-not-allowed'
            )}
          >
            <SkipBack className="w-5 h-5 text-text-secondary" />
          </motion.button>

          {/* Play/Pause - Hero button */}
          <motion.button
            onClick={togglePlayPause}
            disabled={isLoading || !!error}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.92 }}
            className={clsx(
              'audio-play-btn',
              isPlaying && 'playing-pulse',
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

          {/* Next */}
          <motion.button
            onClick={handleNext}
            disabled={!hasNext}
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className={clsx(
              'audio-transport-btn p-2.5',
              !hasNext && 'opacity-30 cursor-not-allowed'
            )}
          >
            <SkipForward className="w-5 h-5 text-text-secondary" />
          </motion.button>
        </div>

        {/* Waveform Container */}
        <div className="flex-1 relative">
          {/* Loading overlay */}
          <AnimatePresence>
            {isLoading && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="absolute inset-0 flex items-center justify-center bg-surface-sunken dark:bg-surface-dark-sunken rounded-xl z-10"
              >
                <div className="flex items-center gap-2 text-text-muted">
                  <motion.div
                    animate={{ rotate: 360 }}
                    transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                  >
                    <Volume2 className="w-5 h-5" />
                  </motion.div>
                  <span className="text-body-sm">Loading waveform...</span>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Error overlay */}
          <AnimatePresence>
            {error && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="absolute inset-0 flex items-center justify-center bg-red-50 dark:bg-red-900/20 rounded-xl z-10"
              >
                <span className="text-body-sm text-danger">{error}</span>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Waveform */}
          <div
            ref={containerRef}
            className={clsx(
              'audio-waveform transition-all duration-300',
              isHovering && !isLoading && !error && 'ring-2 ring-amber-500/20'
            )}
          />
        </div>

        {/* Time Display */}
        <div className="flex flex-col items-end min-w-[90px]">
          <span className="audio-time text-text-primary font-medium">
            {formatTime(currentTime)}
          </span>
          <span className="audio-time text-text-muted text-caption">
            / {formatTime(duration)}
          </span>
        </div>
      </div>

      {/* Progress percentage indicator (subtle) */}
      {duration > 0 && (
        <div className="mt-3 flex items-center justify-between px-1 text-caption text-text-muted">
          <span>{Math.round((currentTime / duration) * 100)}% played</span>
          <span>{formatTime(duration - currentTime)} remaining</span>
        </div>
      )}
    </motion.div>
  )
}

/**
 * DESIGN NOTES:
 *
 * 1. PLAY BUTTON:
 *    - Large (56x56px) for easy targeting
 *    - Gradient background (amber-400 to amber-600)
 *    - Glowing shadow on hover
 *    - Pulsing animation when playing
 *    - Icon rotates on play/pause transition
 *
 * 2. WAVEFORM:
 *    - Taller (64px) for better visual presence
 *    - Thicker bars (3px) with rounded corners
 *    - Brand amber color for progress
 *    - Subtle ring highlight on hover
 *
 * 3. TRANSPORT BUTTONS:
 *    - Clean circular buttons with border
 *    - Scale animation on hover/tap
 *    - Amber border on hover
 *
 * 4. TIME DISPLAY:
 *    - Mono font for tabular numerals
 *    - Stacked layout (current / total)
 *    - Additional progress info below waveform
 *
 * 5. ANIMATIONS:
 *    - Entrance animation (fade + slide)
 *    - Play/pause icon rotation
 *    - Loading spinner
 *    - Smooth transitions throughout
 *
 * 6. EMPTY/ERROR STATES:
 *    - Clear visual feedback
 *    - Helpful messaging
 *    - Consistent styling
 */
