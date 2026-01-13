import { useState, useEffect } from 'react'
import { clsx } from 'clsx'
import { useAppStore } from './stores/appStore'
import { Sidebar } from './components/Sidebar'
import { TrainTab } from './components/TrainTab'
import { TagTab } from './components/TagTab'
import { RefineTab } from './components/RefineTab'
import { SettingsTab } from './components/SettingsTab'
import { StatusBar } from './components/StatusBar'
import { ToastHost } from './components/ToastHost'

export type TabId = 'train' | 'tag' | 'refine' | 'settings'

function App() {
  const [activeTab, setActiveTab] = useState<TabId>('train')
  const { checkServerStatus } = useAppStore()

  useEffect(() => {
    // Check server status on mount
    checkServerStatus()

    // Poll server status every 5 seconds
    const interval = setInterval(checkServerStatus, 5000)
    return () => clearInterval(interval)
  }, [checkServerStatus])

  useEffect(() => {
    const loadingEl = document.getElementById('app-loading')
    if (!loadingEl) return
    loadingEl.classList.add('fade-out')
    const timer = window.setTimeout(() => {
      loadingEl.remove()
    }, 600)
    return () => window.clearTimeout(timer)
  }, [])

  return (
    <div className="flex h-screen bg-sidebar dark:bg-sidebar-dark">
      {/* Sidebar */}
      <Sidebar activeTab={activeTab} onTabChange={setActiveTab} />

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden">
        {/* Tab Content */}
        <div className="flex-1 overflow-auto bg-surface dark:bg-surface-dark">
          <div className={clsx(activeTab !== 'train' && 'hidden')}>
            <TrainTab />
          </div>
          <div className={clsx(activeTab !== 'tag' && 'hidden')}>
            <TagTab />
          </div>
          <div className={clsx(activeTab !== 'refine' && 'hidden')}>
            <RefineTab />
          </div>
          <div className={clsx(activeTab !== 'settings' && 'hidden')}>
            <SettingsTab />
          </div>
        </div>

        {/* Toasts */}
        <ToastHost />

        {/* Status Bar */}
        <StatusBar />
      </main>
    </div>
  )
}

export default App
