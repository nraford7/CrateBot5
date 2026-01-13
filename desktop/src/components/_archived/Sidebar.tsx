import { GraduationCap, Tags, Sliders, Settings, Disc3 } from 'lucide-react'
import { clsx } from 'clsx'
import { motion } from 'framer-motion'
import type { TabId } from '../App'
import { useAppStore } from '../stores/appStore'

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

function CrateBotLogo({ isAnimating = false }: { isAnimating?: boolean }) {
  return (
    <div className="sidebar-logo">
      <div className="sidebar-logo-icon">
        <motion.div
          animate={isAnimating ? { rotate: 360 } : { rotate: 0 }}
          transition={{
            duration: 3,
            repeat: isAnimating ? Infinity : 0,
            ease: 'linear',
          }}
        >
          <Disc3 className="w-4 h-4 text-white drop-shadow-sm" />
        </motion.div>
      </div>
      <span className="sidebar-logo-text">
        Crate<span className="text-amber-500">Bot</span>
      </span>
    </div>
  )
}

export function Sidebar({ activeTab, onTabChange }: SidebarProps) {
  const { currentTask } = useAppStore()
  const isSettingsActive = activeTab === 'settings'
  const isProcessing = !!currentTask

  return (
    <aside className="sidebar relative w-56 flex flex-col border-r border-border-light dark:border-border-dark">
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
              <motion.div
                whileHover={{ scale: 1.1 }}
                whileTap={{ scale: 0.95 }}
                transition={{ type: 'spring', stiffness: 400, damping: 17 }}
              >
                <Icon className="w-[18px] h-[18px]" />
              </motion.div>

              <div className="flex-1 min-w-0">
                <div className="font-medium">{tab.label}</div>
                {!isActive && (
                  <div className="text-xs text-stone-400 dark:text-stone-500 truncate opacity-0 group-hover:opacity-100 transition-opacity">
                    {tab.description}
                  </div>
                )}
              </div>

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

        <div className="px-3 flex items-center justify-between">
          <span className="text-xs text-stone-400 dark:text-stone-500">Version</span>
          <span className="text-xs font-mono text-stone-400 dark:text-stone-500 bg-surface-sunken dark:bg-surface-dark-sunken px-1.5 py-0.5 rounded">
            3.0.0
          </span>
        </div>
      </div>
    </aside>
  )
}
