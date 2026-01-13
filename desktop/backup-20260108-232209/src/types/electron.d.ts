/**
 * Type declarations for Electron APIs exposed via preload
 */

interface ElectronDialog {
  openDirectory: () => Promise<string | null>
  openFiles: (options?: { filters?: { name: string; extensions: string[] }[] }) => Promise<string[]>
  saveFile: (options?: { defaultPath?: string; filters?: { name: string; extensions: string[] }[] }) => Promise<string | null>
}

interface ElectronShell {
  openExternal: (url: string) => Promise<void>
  showItemInFolder: (path: string) => Promise<void>
}

interface ElectronPython {
  isRunning: () => Promise<boolean>
  restart: () => Promise<boolean>
}

interface ElectronApp {
  getVersion: () => Promise<string>
  getPaths: () => Promise<{ home: string; userData: string; temp: string }>
}

interface ElectronAPI {
  dialog: ElectronDialog
  shell: ElectronShell
  python: ElectronPython
  app: ElectronApp
}

declare global {
  interface Window {
    electron?: ElectronAPI
  }
}

export {}
