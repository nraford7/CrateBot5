/**
 * Hook for accessing Electron APIs
 * Falls back to browser alternatives when not in Electron
 */

export function useElectron() {
  const isElectron = typeof window !== 'undefined' && window.electron !== undefined

  const openDirectory = async (): Promise<string | null> => {
    if (isElectron) {
      try {
        const result = await window.electron!.dialog.openDirectory()
        return result
      } catch (error) {
        console.error('Failed to open directory dialog:', error)
        return null
      }
    }
    // Fallback for non-Electron environments
    console.warn('Electron dialog not available - window.electron:', typeof window !== 'undefined' ? window.electron : 'undefined')
    return null
  }

  const openFiles = async (options?: { filters?: { name: string; extensions: string[] }[] }): Promise<string[]> => {
    if (isElectron) {
      try {
        const result = await window.electron!.dialog.openFiles(options)
        return result
      } catch (error) {
        console.error('Failed to open files dialog:', error)
        return []
      }
    }
    // Fallback for non-Electron environments
    console.warn('Electron dialog not available - window.electron:', typeof window !== 'undefined' ? window.electron : 'undefined')
    return []
  }

  const saveFile = async (options?: { defaultPath?: string }): Promise<string | null> => {
    if (isElectron) {
      try {
        const result = await window.electron!.dialog.saveFile(options)
        return result
      } catch (error) {
        console.error('Failed to open save dialog:', error)
        return null
      }
    }
    // Fallback: prompt for path
    return prompt('Enter save path:', options?.defaultPath)
  }

  const openExternal = async (url: string): Promise<void> => {
    if (isElectron) {
      return window.electron!.shell.openExternal(url)
    }
    window.open(url, '_blank')
  }

  const showItemInFolder = async (path: string): Promise<void> => {
    if (isElectron) {
      return window.electron!.shell.showItemInFolder(path)
    }
    console.log('Show in folder not available:', path)
  }

  const isPythonRunning = async (): Promise<boolean> => {
    if (isElectron) {
      return window.electron!.python.isRunning()
    }
    return false
  }

  const restartPython = async (): Promise<boolean> => {
    if (isElectron) {
      return window.electron!.python.restart()
    }
    return false
  }

  const getAppVersion = async (): Promise<string> => {
    if (isElectron) {
      return window.electron!.app.getVersion()
    }
    return '3.0.0-dev'
  }

  return {
    isElectron,
    dialog: {
      openDirectory,
      openFiles,
      saveFile,
    },
    shell: {
      openExternal,
      showItemInFolder,
    },
    python: {
      isRunning: isPythonRunning,
      restart: restartPython,
    },
    app: {
      getVersion: getAppVersion,
    },
  }
}
