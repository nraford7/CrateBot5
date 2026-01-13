import { GraduationCap, Tags, Sliders, Settings, Disc3 } from 'lucide-react'
import { clsx } from 'clsx'
import type { TabId } from '../App'

interface SidebarProps {
  activeTab: TabId
  onTabChange: (tab: TabId) => void
}

const mainTabs = [
  { id: 'train' as const, label: 'Train', icon: GraduationCap },
  { id: 'tag' as const, label: 'Tag', icon: Tags },
  { id: 'refine' as const, label: 'Refine', icon: Sliders },
]

export function Sidebar({ activeTab, onTabChange }: SidebarProps) {
  const isSettingsActive = activeTab === 'settings'

  return (
    <aside className="w-56 bg-sidebar dark:bg-sidebar-dark border-r border-border dark:border-border-dark flex flex-col">
      {/* Spacer for macOS traffic lights */}
      <div className="h-7 drag-region" />

      {/* App Title - Drag Region */}
      <div className="h-12 flex items-center px-4 drag-region border-b border-border dark:border-border-dark">
        <div className="flex items-center gap-2 no-drag">
          <Disc3 className="w-5 h-5 text-accent" />
          <span className="font-semibold text-gray-900 dark:text-white">CrateBot</span>
        </div>
      </div>

      {/* Main Navigation */}
      <nav className="flex-1 p-2 space-y-1">
        {mainTabs.map((tab) => {
          const Icon = tab.icon
          const isActive = activeTab === tab.id

          return (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={clsx(
                'w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors',
                isActive
                  ? 'bg-accent text-white'
                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
              )}
            >
              <Icon className="w-4 h-4" />
              {tab.label}
            </button>
          )
        })}
      </nav>

      {/* Settings at bottom */}
      <div className="p-2 border-t border-border dark:border-border-dark">
        <button
          onClick={() => onTabChange('settings')}
          className={clsx(
            'w-full flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors',
            isSettingsActive
              ? 'bg-accent text-white'
              : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800'
          )}
        >
          <Settings className="w-4 h-4" />
          Settings
        </button>
      </div>

      {/* Version */}
      <div className="px-4 pb-4 pt-2 text-xs text-muted">
        v3.0.0
      </div>
    </aside>
  )
}
