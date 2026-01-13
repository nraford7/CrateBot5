/**
 * CrateBot App - Redesigned with Setup-First Flow
 * Main application component with streamlined tagging experience
 */
import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAppStore } from './stores/appStore'
import { SetupWizard } from './components/SetupWizard'
import { MainHeader } from './components/MainHeader'
import { TaggingView } from './components/TaggingView'
import { SettingsPanel } from './components/SettingsPanel'
import { TrainTab } from './components/TrainTab'
import { RefineTab } from './components/RefineTab'
import { StatusBar } from './components/StatusBar'
import { ToastHost } from './components/ToastHost'

type AdvancedView = 'none' | 'train' | 'refine'

function App() {
  const { setupComplete, pendingView, clearPendingView, checkServerStatus } = useAppStore()
  const [settingsOpen, setSettingsOpen] = useState(false)
  // advancedView controls which main view is shown (tagging, train, or refine)
  const [advancedView, setAdvancedViewState] = useState<AdvancedView>('none')

  // Derive effective view: pendingView takes precedence during transition from wizard
  // This ensures we show the correct view immediately without waiting for state updates
  const effectiveView: AdvancedView = (pendingView === 'train' ? 'train' : advancedView)

  // Wrapper to set advancedView - clears pendingView if we're navigating away from it
  const setAdvancedView = (view: AdvancedView) => {
    setAdvancedViewState(view)
  }

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

  // Handle navigation from TaggingView completion dialog
  useEffect(() => {
    const handleNavigateToRefine = () => {
      setAdvancedView('refine')
      setSettingsOpen(false)
    }
    window.addEventListener('navigate-to-refine', handleNavigateToRefine)
    return () => window.removeEventListener('navigate-to-refine', handleNavigateToRefine)
  }, [])

  // Step 1: Sync local state with pendingView when it changes
  useEffect(() => {
    if (pendingView) {
      setAdvancedViewState(pendingView)
    }
  }, [pendingView])

  // Step 2: Clear pendingView only AFTER local state has been updated to match
  // This prevents a race where Zustand re-renders before React state updates
  useEffect(() => {
    if (pendingView && advancedView === pendingView) {
      clearPendingView()
    }
  }, [pendingView, advancedView, clearPendingView])

  // Show setup wizard if not complete
  if (!setupComplete) {
    return <SetupWizard />
  }

  // Main app view
  return (
    <div className="flex flex-col h-screen bg-surface-sunken dark:bg-surface-dark-sunken">
      {/* Header */}
      <MainHeader onOpenSettings={() => setSettingsOpen(true)} />

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden">
        <div className="flex-1 overflow-auto bg-surface-light dark:bg-surface-dark">
          <AnimatePresence mode="wait">
            {effectiveView === 'none' && (
              <motion.div
                key="tagging"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="h-full"
              >
                <TaggingView />
              </motion.div>
            )}
            {effectiveView === 'train' && (
              <motion.div
                key="train"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="h-full"
              >
                <div className="p-4">
                  <button
                    onClick={() => setAdvancedView('none')}
                    className="btn btn-secondary mb-4"
                  >
                    ← Back to Tagging
                  </button>
                </div>
                <TrainTab />
              </motion.div>
            )}
            {effectiveView === 'refine' && (
              <motion.div
                key="refine"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
                className="h-full"
              >
                <div className="p-4">
                  <button
                    onClick={() => setAdvancedView('none')}
                    className="btn btn-secondary mb-4"
                  >
                    ← Back to Tagging
                  </button>
                </div>
                <RefineTab />
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Toasts */}
        <ToastHost />

        {/* Status Bar */}
        <StatusBar />
      </main>

      {/* Settings Panel */}
      <SettingsPanel
        isOpen={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        onOpenTrain={() => setAdvancedView('train')}
        onOpenRefine={() => setAdvancedView('refine')}
      />
    </div>
  )
}

export default App
