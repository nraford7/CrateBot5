/**
 * CrateBot3 - Redesigned TagTab
 * "Vinyl Warmth" Design System
 *
 * This shows the full page design with:
 * - Distinctive page header
 * - Redesigned cards
 * - Better drop zone
 * - Improved file queue
 * - Animated interactions
 */

import { useEffect, useState } from 'react'
import {
  FilePlus,
  Play,
  Square,
  AlertCircle,
  FolderOpen,
  Loader2,
  Upload,
  Disc3,
  CheckCircle2,
  XCircle,
  Clock,
} from 'lucide-react'
import { motion, AnimatePresence } from 'framer-motion'
import { clsx } from 'clsx'

// Animation variants for staggered children
const containerVariants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.08,
      delayChildren: 0.1,
    },
  },
}

const itemVariants = {
  hidden: { opacity: 0, y: 15 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.4, ease: [0.4, 0, 0.2, 1] },
  },
}

// Page Header Component
function PageHeader({
  title,
  description,
}: {
  title: string
  description: string
}) {
  return (
    <motion.div variants={itemVariants} className="mb-8">
      <h1 className="font-display text-display-sm text-text-primary mb-2">
        {title}
      </h1>
      <p className="text-body-md text-text-secondary max-w-xl">{description}</p>
    </motion.div>
  )
}

// Enhanced Card Component
function Card({
  children,
  className,
  title,
  icon: Icon,
  action,
}: {
  children: React.ReactNode
  className?: string
  title?: string
  icon?: any
  action?: React.ReactNode
}) {
  return (
    <motion.div variants={itemVariants} className={clsx('card', className)}>
      {(title || Icon || action) && (
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            {Icon && (
              <div className="w-8 h-8 rounded-lg bg-amber-100 dark:bg-amber-900/30 flex items-center justify-center">
                <Icon className="w-4 h-4 text-amber-600 dark:text-amber-400" />
              </div>
            )}
            {title && (
              <h2 className="font-display font-semibold text-heading-md text-text-primary">
                {title}
              </h2>
            )}
          </div>
          {action}
        </div>
      )}
      {children}
    </motion.div>
  )
}

// Enhanced Drop Zone
function DropZone({
  onDrop,
  isDragging,
  onSelectFiles,
  disabled,
}: {
  onDrop: (paths: string[]) => void
  isDragging: boolean
  onSelectFiles: () => void
  disabled: boolean
}) {
  return (
    <motion.div
      variants={itemVariants}
      className={clsx(
        'relative rounded-xl border-2 border-dashed p-8 text-center transition-all duration-200',
        isDragging
          ? 'border-amber-500 bg-amber-50 dark:bg-amber-900/10'
          : 'border-border-light dark:border-border-dark hover:border-amber-300 dark:hover:border-amber-700',
        disabled && 'opacity-50 pointer-events-none'
      )}
    >
      {/* Drag overlay */}
      <AnimatePresence>
        {isDragging && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="absolute inset-0 rounded-xl bg-amber-500/10 backdrop-blur-sm flex flex-col items-center justify-center z-10"
          >
            <motion.div
              animate={{ y: [0, -8, 0] }}
              transition={{ duration: 1, repeat: Infinity }}
            >
              <Upload className="w-12 h-12 text-amber-500 mb-3" />
            </motion.div>
            <p className="text-heading-md font-display font-semibold text-amber-600">
              Drop MP3 files here
            </p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Default content */}
      <div className="flex flex-col items-center">
        <div className="w-16 h-16 rounded-2xl bg-surface-sunken dark:bg-surface-dark-sunken flex items-center justify-center mb-4">
          <Disc3 className="w-8 h-8 text-text-muted" />
        </div>
        <p className="text-body-lg font-medium text-text-primary mb-1">
          Drag and drop MP3 files
        </p>
        <p className="text-body-sm text-text-muted mb-4">or</p>
        <button onClick={onSelectFiles} className="btn btn-secondary">
          <FolderOpen className="w-4 h-4" />
          Browse Files
        </button>
      </div>
    </motion.div>
  )
}

// Tagging Option Checkbox
function TagOption({
  label,
  checked,
  onChange,
  disabled,
  badge,
}: {
  label: string
  checked: boolean
  onChange: (checked: boolean) => void
  disabled?: boolean
  badge?: string
}) {
  return (
    <label
      className={clsx(
        'flex items-center gap-2.5 py-2 cursor-pointer group',
        disabled && 'opacity-50 cursor-not-allowed'
      )}
    >
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        disabled={disabled}
        className="checkbox"
      />
      <span className="text-body-md text-text-primary group-hover:text-amber-600 dark:group-hover:text-amber-400 transition-colors">
        {label}
      </span>
      {badge && (
        <span className="badge badge-warning text-caption">{badge}</span>
      )}
    </label>
  )
}

// File Queue Item
function FileQueueItem({
  name,
  status,
  isActive,
}: {
  name: string
  status: 'pending' | 'processing' | 'tagged' | 'failed'
  isActive?: boolean
}) {
  const statusConfig = {
    pending: { icon: Clock, color: 'text-text-muted' },
    processing: { icon: Loader2, color: 'text-amber-500', spin: true },
    tagged: { icon: CheckCircle2, color: 'text-success' },
    failed: { icon: XCircle, color: 'text-danger' },
  }[status]

  const Icon = statusConfig.icon

  return (
    <motion.div
      layout
      initial={{ opacity: 0, x: -10 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: 10 }}
      className={clsx(
        'file-queue-item',
        isActive && 'active',
        status === 'processing' && 'processing'
      )}
    >
      <Icon
        className={clsx(
          'w-4 h-4 flex-shrink-0',
          statusConfig.color,
          statusConfig.spin && 'animate-spin'
        )}
      />
      <span className="flex-1 text-body-sm text-text-primary truncate">
        {name}
      </span>
    </motion.div>
  )
}

// Main Component (simplified for mockup)
export function TagTab() {
  const [isDragging, setIsDragging] = useState(false)

  // Mock data for demonstration
  const mockFiles = [
    { name: 'summer-vibes-mix.mp3', status: 'tagged' as const },
    { name: 'deep-house-session.mp3', status: 'tagged' as const },
    { name: 'late-night-grooves.mp3', status: 'processing' as const },
    { name: 'sunset-drive.mp3', status: 'pending' as const },
    { name: 'morning-coffee.mp3', status: 'pending' as const },
  ]

  return (
    <motion.div
      variants={containerVariants}
      initial="hidden"
      animate="visible"
      className="p-8 max-w-4xl"
    >
      {/* Page Header */}
      <PageHeader
        title="Tag Files"
        description="Apply ML-predicted tags and AI-generated vibes to your music collection."
      />

      {/* Model Card */}
      <Card title="Model" icon={Disc3} className="mb-6">
        <div className="flex gap-3 items-center">
          <input
            type="text"
            placeholder="Select a model to use for tagging..."
            className="input flex-1"
            disabled
          />
          <button className="btn btn-secondary">
            <FolderOpen className="w-4 h-4" />
            Browse
          </button>
        </div>
        <p className="text-caption text-text-muted mt-2">
          Train a new model or browse to select an existing one.
        </p>
      </Card>

      {/* Tagging Options */}
      <Card title="Tagging Options" className="mb-6">
        <div className="grid grid-cols-2 md:grid-cols-3 gap-x-6 gap-y-1">
          <TagOption label="Genre" checked={true} onChange={() => {}} />
          <TagOption label="Album (Mood)" checked={true} onChange={() => {}} />
          <TagOption label="Comments" checked={true} onChange={() => {}} />
          <TagOption label="Likeness Scores" checked={true} onChange={() => {}} />
          <TagOption
            label="Generate Vibes"
            checked={true}
            onChange={() => {}}
            badge="AI"
          />
          <TagOption
            label="Detect Hooks"
            checked={false}
            onChange={() => {}}
            badge="AI"
          />

          <div className="col-span-full border-t border-border-light dark:border-border-dark my-2" />

          <TagOption
            label="Overwrite existing tags"
            checked={true}
            onChange={() => {}}
          />
        </div>
      </Card>

      {/* Drop Zone */}
      <DropZone
        onDrop={() => {}}
        isDragging={isDragging}
        onSelectFiles={() => {}}
        disabled={false}
      />

      {/* File Queue */}
      {mockFiles.length > 0 && (
        <motion.div variants={itemVariants} className="mt-6">
          <Card className="p-0 overflow-hidden">
            {/* Header */}
            <div className="flex items-center justify-between px-4 py-3 bg-surface-sunken dark:bg-surface-dark-sunken border-b border-border-light dark:border-border-dark">
              <div className="flex items-center gap-4">
                <span className="font-medium text-text-primary">
                  {mockFiles.length} files
                </span>
                <div className="flex items-center gap-3 text-caption">
                  <span className="flex items-center gap-1 text-success">
                    <CheckCircle2 className="w-3 h-3" /> 2
                  </span>
                  <span className="flex items-center gap-1 text-amber-500">
                    <Loader2 className="w-3 h-3 animate-spin" /> 1
                  </span>
                  <span className="flex items-center gap-1 text-text-muted">
                    <Clock className="w-3 h-3" /> 2
                  </span>
                </div>
              </div>
            </div>

            {/* File list */}
            <div className="max-h-64 overflow-auto">
              <AnimatePresence>
                {mockFiles.map((file, index) => (
                  <FileQueueItem
                    key={file.name}
                    name={file.name}
                    status={file.status}
                    isActive={file.status === 'processing'}
                  />
                ))}
              </AnimatePresence>
            </div>

            {/* Progress bar */}
            <div className="px-4 py-3 bg-surface-sunken dark:bg-surface-dark-sunken border-t border-border-light dark:border-border-dark">
              <div className="flex justify-between text-caption mb-1.5">
                <span className="text-text-muted">Progress</span>
                <span className="font-medium font-mono">3 / 5</span>
              </div>
              <div className="progress-track">
                <div className="progress-bar-animated" style={{ width: '60%' }} />
              </div>
            </div>
          </Card>
        </motion.div>
      )}

      {/* Action Button */}
      <motion.div
        variants={itemVariants}
        className="mt-6 flex items-center gap-3"
      >
        <button className="btn btn-primary">
          <Play className="w-4 h-4" />
          Start Tagging (2 files)
        </button>
      </motion.div>
    </motion.div>
  )
}

/**
 * DESIGN NOTES:
 *
 * 1. PAGE STRUCTURE:
 *    - Staggered entrance animations for all cards
 *    - Consistent spacing (mb-6 between cards)
 *    - max-w-4xl for readable line lengths
 *    - p-8 for comfortable page padding
 *
 * 2. CARDS:
 *    - Icon badges in colored squares
 *    - Display font for titles
 *    - Optional action slot in header
 *
 * 3. DROP ZONE:
 *    - Dashed border (2px for visibility)
 *    - Amber highlight on drag
 *    - Bouncing upload icon
 *    - Clear call-to-action
 *
 * 4. FILE QUEUE:
 *    - Layout animations for smooth reordering
 *    - Status-specific styling (active, processing)
 *    - Mini progress bar with shimmer animation
 *    - Clear status indicators
 *
 * 5. OPTIONS:
 *    - Checkbox with brand amber color
 *    - Badge for AI features
 *    - Hover state on labels
 *
 * 6. TYPOGRAPHY:
 *    - Display font for page title
 *    - Consistent caption size for metadata
 *    - Mono font for counts/percentages
 */
