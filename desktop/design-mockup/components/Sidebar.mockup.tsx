/**
 * CrateBot3 - Redesigned Sidebar
 * "Vinyl Warmth" Design System
 *
 * Key changes:
 * - Distinctive logo with vinyl-inspired icon
 * - Warmer color palette
 * - Smooth active state animations
 * - Better visual hierarchy
 * - Subtle background texture
 */

import { GraduationCap, Tags, Sliders, Settings, Disc3 } from 'lucide-react'
import { clsx } from 'clsx'
import { motion } from 'framer-motion'
import type { TabId } from '../App'

interface SidebarProps {
  activeTab: TabId
  onTabChange: (tab: TabId) => void
}

const mainTabs = [
  {
    id: 'train' as const,
    label: 'Train',
    icon: GraduationCap,
    description: 'Build your model',
  },
  {
    id: 'tag' as const,
    label: 'Tag',
    icon: Tags,
    description: 'Process your files',
  },
  {
    id: 'refine' as const,
    label: 'Refine',
    icon: Sliders,
    description: 'Review & correct',
  },
]

// Vinyl-inspired logo component
function CrateBotLogo({ isAnimating = false }: { isAnimating?: boolean }) {
  return (
    <div className="sidebar-logo">
      {/* Vinyl disc icon with gradient */}
      <div className="sidebar-logo-icon group">
        <motion.div
          animate={isAnimating ? { rotate: 360 } : { rotate: 0 }}
          transition={{
            duration: 3,
            repeat: isAnimating ? Infinity : 0,
            ease: 'linear',
          }}
        >
          <Disc3 className="w-5 h-5 text-white drop-shadow-sm" />
        </motion.div>
      </div>

      {/* Brand name with display font */}
      <span className="sidebar-logo-text">
        Crate<span className="text-amber-500">Bot</span>
      </span>
    </div>
  )
}

export function Sidebar({ activeTab, onTabChange }: SidebarProps) {
  const isSettingsActive = activeTab === 'settings'
  const isProcessing = false // Would come from store in real implementation

  return (
    <aside className="sidebar relative w-56 flex flex-col border-r border-border-light dark:border-border-dark noise-overlay">
      {/* Spacer for macOS traffic lights */}
      <div className="h-7 drag-region" />

      {/* Logo Header */}
      <div className="h-14 flex items-center px-4 drag-region">
        <div className="no-drag">
          <CrateBotLogo isAnimating={isProcessing} />
        </div>
      </div>

      {/* Main Navigation */}
      <nav className="flex-1 p-3 space-y-1">
        {mainTabs.map((tab, index) => {
          const Icon = tab.icon
          const isActive = activeTab === tab.id

          return (
            <motion.button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: index * 0.05, duration: 0.2 }}
              className={clsx(
                'sidebar-nav-item w-full text-left group',
                isActive && 'active'
              )}
            >
              {/* Icon with subtle animation on hover */}
              <motion.div
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: 'spring', stiffness: 400, damping: 17 }}
              >
                <Icon className="w-[18px] h-[18px]" />
              </motion.div>

              {/* Label and description */}
              <div className="flex-1 min-w-0">
                <div className="font-medium">{tab.label}</div>
                {!isActive && (
                  <div className="text-caption text-text-muted truncate opacity-0 group-hover:opacity-100 transition-opacity">
                    {tab.description}
                  </div>
                )}
              </div>

              {/* Active indicator dot */}
              {isActive && (
                <motion.div
                  layoutId="activeIndicator"
                  className="w-1.5 h-1.5 rounded-full bg-white/80"
                  transition={{ type: 'spring', stiffness: 500, damping: 30 }}
                />
              )}
            </motion.button>
          )
        })}
      </nav>

      {/* Bottom Section */}
      <div className="p-3 border-t border-border-light dark:border-border-dark space-y-3">
        {/* Settings button */}
        <button
          onClick={() => onTabChange('settings')}
          className={clsx(
            'sidebar-nav-item w-full text-left',
            isSettingsActive && 'active'
          )}
        >
          <Settings className="w-[18px] h-[18px]" />
          <span className="flex-1">Settings</span>
        </button>

        {/* Version with subtle styling */}
        <div className="px-3 flex items-center justify-between">
          <span className="text-caption text-text-muted">Version</span>
          <span className="text-caption font-mono text-text-muted bg-surface-sunken dark:bg-surface-dark-sunken px-1.5 py-0.5 rounded">
            3.0.0
          </span>
        </div>
      </div>
    </aside>
  )
}

/**
 * DESIGN NOTES:
 *
 * 1. LOGO:
 *    - Gradient vinyl disc icon (amber-400 to amber-600)
 *    - Spins when processing is active
 *    - "Bot" in brand amber color for visual break
 *    - Uses Satoshi display font (bold, modern)
 *
 * 2. NAVIGATION:
 *    - Warm amber active state with glow shadow
 *    - Staggered entrance animation
 *    - Hover reveals description text
 *    - Active indicator dot with layout animation
 *    - Icons scale on hover for tactile feedback
 *
 * 3. COLORS:
 *    - Sidebar background: #f0eeeb (warm gray)
 *    - Active: amber-500 with warm shadow
 *    - Text: warm neutrals (stone palette)
 *
 * 4. MICRO-INTERACTIONS:
 *    - Icon scale on hover (spring physics)
 *    - Description fade in on hover
 *    - Layout animation for active indicator
 *    - Vinyl spin during processing
 *
 * 5. SUBTLE TEXTURE:
 *    - noise-overlay class adds 3% noise texture
 *    - Creates analog/vintage feel without being overwhelming
 */
