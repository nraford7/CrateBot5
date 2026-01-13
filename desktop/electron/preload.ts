import { contextBridge, ipcRenderer } from 'electron'

/**
 * Preload script - exposes safe Electron APIs to the renderer
 */

// Dialog APIs
const dialog = {
  openDirectory: (): Promise<string | null> =>
    ipcRenderer.invoke('dialog:openDirectory'),

  openFiles: (options?: { filters?: { name: string; extensions: string[] }[] }): Promise<string[]> =>
    ipcRenderer.invoke('dialog:openFiles', options),

  saveFile: (options?: { defaultPath?: string; filters?: { name: string; extensions: string[] }[] }): Promise<string | null> =>
    ipcRenderer.invoke('dialog:saveFile', options),
}

// Shell APIs
const shell = {
  openExternal: (url: string): Promise<void> =>
    ipcRenderer.invoke('shell:openExternal', url),

  showItemInFolder: (path: string): Promise<void> =>
    ipcRenderer.invoke('shell:showItemInFolder', path),
}

// Python server APIs
const python = {
  isRunning: (): Promise<boolean> =>
    ipcRenderer.invoke('python:isRunning'),

  restart: (): Promise<boolean> =>
    ipcRenderer.invoke('python:restart'),
}

// Model APIs
const model = {
  getBundledPath: (): Promise<string | null> =>
    ipcRenderer.invoke('model:getBundledPath'),
}

// App APIs
const appInfo = {
  getVersion: (): Promise<string> =>
    ipcRenderer.invoke('app:getVersion'),

  getPaths: (): Promise<{ home: string; userData: string; temp: string }> =>
    ipcRenderer.invoke('app:getPaths'),
}

// Logging API (renderer -> main log)
const log = {
  write: (message: string): void =>
    ipcRenderer.send('log:write', message),
}

// Expose APIs to renderer
contextBridge.exposeInMainWorld('electron', {
  dialog,
  shell,
  python,
  model,
  app: appInfo,
  log,
})

// Type declaration for the renderer
declare global {
  interface Window {
    electron: {
      dialog: typeof dialog
      shell: typeof shell
      python: typeof python
      model: typeof model
      app: typeof appInfo
      log: typeof log
    }
  }
}
