import { app, BrowserWindow, ipcMain, dialog, shell, Menu, protocol, net as electronNet } from 'electron'
import { spawn, ChildProcess } from 'child_process'
import electronUpdater from 'electron-updater'
const { autoUpdater } = electronUpdater
import path from 'path'
import { fileURLToPath, pathToFileURL } from 'url'
import fs from 'fs'
import net from 'net'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

// Configure auto-updater
autoUpdater.autoDownload = false
autoUpdater.autoInstallOnAppQuit = true

// Python server process
let pythonProcess: ChildProcess | null = null
let mainWindow: BrowserWindow | null = null
let splashWindow: BrowserWindow | null = null
let serverLogPath: string | null = null
let appLogPath: string | null = null
let serverStartInFlight: Promise<void> | null = null

const logMain = (message: string) => {
  console.log(message)
  if (!appLogPath) return
  try {
    const line = `${new Date().toISOString()} ${message}\n`
    fs.appendFileSync(appLogPath, line)
  } catch (error) {
    console.error('Failed to write app log:', error)
  }
}

ipcMain.on('log:write', (_event, message) => {
  const text = typeof message === 'string' ? message : JSON.stringify(message)
  logMain(`[renderer] ${text}`)
})

const SERVER_URL = 'http://127.0.0.1:8742/api/v1/health'
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

const isPortOpen = (port: number, host = '127.0.0.1', timeoutMs = 500): Promise<boolean> => {
  return new Promise((resolve) => {
    const socket = new net.Socket()
    const onDone = (result: boolean) => {
      socket.removeAllListeners()
      socket.destroy()
      resolve(result)
    }

    socket.setTimeout(timeoutMs)
    socket.once('connect', () => onDone(true))
    socket.once('timeout', () => onDone(false))
    socket.once('error', () => onDone(false))
    socket.connect(port, host)
  })
}

const checkServerHealth = async (timeoutMs = 1000): Promise<boolean> => {
  try {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), timeoutMs)
    const response = await fetch(SERVER_URL, { signal: controller.signal })
    clearTimeout(timeout)
    if (!response.ok) return false
    const data = await response.json()
    return data?.status === 'ok'
  } catch {
    return false
  }
}

const waitForServerHealthy = async (timeoutMs = 60000, intervalMs = 500): Promise<boolean> => {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    if (await checkServerHealth()) {
      return true
    }
    await sleep(intervalMs)
  }
  return false
}

// Paths
const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged
const projectRoot = isDev
  ? path.join(__dirname, '..', '..')
  : path.join(process.resourcesPath)

const pythonPath = isDev
  ? path.join(projectRoot, 'python')
  : path.join(process.resourcesPath, 'python')

const backendPath = isDev
  ? path.join(projectRoot, 'backend')
  : path.join(process.resourcesPath, 'backend')

/**
 * Register the cratebot:// protocol for secure local file access.
 * This allows the renderer to load audio files using cratebot://path/to/file.mp3
 * instead of file:// which has security restrictions.
 */
function registerProtocol() {
  protocol.handle('cratebot', (request) => {
    // cratebot://path/to/file.mp3 -> /path/to/file.mp3
    const filePath = decodeURIComponent(request.url.replace('cratebot://', ''))

    // Security: Only allow audio files
    const ext = path.extname(filePath).toLowerCase()
    const allowedExtensions = ['.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg', '.aiff']

    if (!allowedExtensions.includes(ext)) {
      return new Response('File type not allowed', { status: 403 })
    }

    // Check file exists
    if (!fs.existsSync(filePath)) {
      return new Response('File not found', { status: 404 })
    }

    // Return the file using net.fetch with file:// URL
    return electronNet.fetch(pathToFileURL(filePath).toString())
  })

  console.log('Registered cratebot:// protocol handler')
}

/**
 * Start the Python FastAPI server
 */
function startPythonServer(): Promise<void> {
  if (serverStartInFlight) {
    return serverStartInFlight
  }

  serverStartInFlight = new Promise((resolve, reject) => {
    logMain('Starting Python server')
    logMain(`isDev: ${String(isDev)}`)
    const cratebotHome = app.getPath('userData')
    if (!serverLogPath) {
      const logDir = path.join(app.getPath('userData'), 'logs')
      fs.mkdirSync(logDir, { recursive: true })
      serverLogPath = path.join(logDir, 'cratebot-server.log')
      fs.writeFileSync(serverLogPath, '')
      logMain(`Server log: ${serverLogPath}`)
    }

    const attachProcessHandlers = () => {
      if (!pythonProcess) return

      pythonProcess.stdout?.on('data', (data) => {
        const output = data.toString()
        console.log('[Python]', output.trim())
        if (serverLogPath) {
          fs.appendFileSync(serverLogPath, output)
        }
      })

      pythonProcess.stderr?.on('data', (data) => {
        const output = data.toString()
        console.error('[Python Error]', output.trim())
        if (serverLogPath) {
          fs.appendFileSync(serverLogPath, output)
        }
      })

      pythonProcess.on('error', (err) => {
        console.error('Failed to start Python server:', err)
        if (serverLogPath) {
          fs.appendFileSync(serverLogPath, `\n[spawn error] ${String(err)}\n`)
        }
        reject(err)
      })

      pythonProcess.on('close', (code) => {
        console.log('Python server exited with code:', code)
        if (serverLogPath) {
          fs.appendFileSync(serverLogPath, `\n[exit] code=${code}\n`)
        }
        pythonProcess = null

      // Restart if unexpected exit while app is running and server isn't healthy
      if (mainWindow && !mainWindow.isDestroyed()) {
          Promise.all([checkServerHealth(), isPortOpen(8742)]).then(([healthy, portOpen]) => {
            if (healthy) {
              logMain('Server health ok after exit; skipping restart')
              return
            }
            if (portOpen) {
              logMain('Port 8742 already in use after exit; skipping restart')
              return
            }
            logMain('Restarting Python server after exit')
            setTimeout(() => startPythonServer(), 1500)
          }).catch(() => {
            logMain('Restarting Python server after exit (health check failed)')
            setTimeout(() => startPythonServer(), 1500)
          })
      }
    })
    }

    const startProcess = () => {
      if (isDev) {
        // Development: use python3 with run_server.py
        const serverScript = path.join(backendPath, 'run_server.py')
        console.log('Script:', serverScript)
        console.log('Python path:', pythonPath)

        const venvPython = process.platform === 'win32'
          ? path.join(projectRoot, 'python', 'venv', 'Scripts', 'python.exe')
          : path.join(projectRoot, 'python', 'venv', 'bin', 'python')
        const pythonExecutable = fs.existsSync(venvPython)
          ? venvPython
          : (process.platform === 'win32' ? 'python' : 'python3')
        const env = {
          ...process.env,
          CRATEBOT_HOME: cratebotHome,
          PYTHONPATH: `${projectRoot}:${pythonPath}`,
          PYTHONUNBUFFERED: '1',
        }

        pythonProcess = spawn(pythonExecutable, [serverScript], {
          cwd: projectRoot,
          env,
          stdio: ['ignore', 'pipe', 'pipe'],
        })
      } else {
        // Production: use bundled cratebot-server binary
        const binaryName = process.platform === 'win32' ? 'cratebot-server.exe' : 'cratebot-server'
        let serverBinary = path.join(process.resourcesPath, binaryName)
        try {
          if (fs.existsSync(serverBinary) && fs.statSync(serverBinary).isDirectory()) {
            serverBinary = path.join(serverBinary, binaryName)
          }
        } catch (error) {
          console.error('Failed to resolve server binary path:', error)
        }

        console.log('Binary:', serverBinary)

        // Check if binary exists
        if (!fs.existsSync(serverBinary)) {
          console.error('Server binary not found:', serverBinary)
          // Fall back to python3 if binary not found
          console.log('Falling back to python3...')
          const serverScript = path.join(backendPath, 'run_server.py')
          const venvPython = process.platform === 'win32'
            ? path.join(projectRoot, 'python', 'venv', 'Scripts', 'python.exe')
            : path.join(projectRoot, 'python', 'venv', 'bin', 'python')
          const pythonExecutable = fs.existsSync(venvPython)
            ? venvPython
            : (process.platform === 'win32' ? 'python' : 'python3')
          const env = {
            ...process.env,
            CRATEBOT_HOME: cratebotHome,
            PYTHONPATH: `${projectRoot}:${pythonPath}`,
            PYTHONUNBUFFERED: '1',
          }

          pythonProcess = spawn(pythonExecutable, [serverScript], {
            cwd: projectRoot,
            env,
            stdio: ['ignore', 'pipe', 'pipe'],
          })
        } else {
          try {
            fs.chmodSync(serverBinary, 0o755)
          } catch (error) {
            console.error('Failed to ensure server binary is executable:', error)
          }
          pythonProcess = spawn(serverBinary, [], {
            cwd: process.resourcesPath,
            env: {
              ...process.env,
              CRATEBOT_HOME: cratebotHome,
            },
            stdio: ['ignore', 'pipe', 'pipe'],
          })
        }
      }

      attachProcessHandlers()
    }

    const finishStart = async () => {
      const healthy = await waitForServerHealthy()
      if (healthy) {
        logMain('Server health check passed')
        resolve()
      } else {
        logMain('Server health check timed out')
        reject(new Error('Server did not become healthy in time'))
      }
    }

    Promise.resolve()
      .then(async () => {
        const healthy = await checkServerHealth()
        if (healthy) {
          logMain('Server already healthy; skipping spawn')
          resolve()
          return true
        }

        const portOpen = await isPortOpen(8742)
        if (portOpen) {
          logMain('Server port open but health not ready; waiting')
          const ready = await waitForServerHealthy(30000, 500)
          if (ready) {
            logMain('Server health check passed after wait')
            resolve()
            return true
          }
          logMain('Server port open but health not responding; skipping spawn')
          reject(new Error('Server unresponsive on port 8742'))
          return true
        }

        return false
      })
      .then((handled) => {
        if (handled) return
        startProcess()
        finishStart().catch(reject)
      })
      .catch((error) => {
        startProcess()
        finishStart().catch((finishError) => {
          reject(finishError || error)
        })
      })
  }).finally(() => {
    serverStartInFlight = null
  })

  return serverStartInFlight
}

/**
 * Stop the Python server
 */
function stopPythonServer() {
  if (pythonProcess) {
    console.log('Stopping Python server...')
    pythonProcess.kill()
    pythonProcess = null
  }
}

function createSplashWindow() {
  // Splash screen styled to match CrateBot's "Vinyl Warmth" theme
  const splashHtml = `
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>CrateBot</title>
        <link rel="preconnect" href="https://fonts.googleapis.com">
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
        <link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@500;600;700&display=swap" rel="stylesheet">
        <style>
          html, body { height: 100%; margin: 0; }
          body {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            background: #1a1918;
            color: #fafaf9;
            font-family: "DM Sans", system-ui, sans-serif;
            font-size: 14px;
          }
          .logo-circle {
            width: 72px;
            height: 72px;
            border-radius: 50%;
            background: rgba(245, 158, 11, 0.12);
            display: flex;
            align-items: center;
            justify-content: center;
            margin-bottom: 20px;
          }
          .logo-circle svg {
            width: 36px;
            height: 36px;
            color: #f59e0b;
          }
          .brand {
            font-size: 28px;
            font-weight: 700;
            margin-bottom: 4px;
            color: #fafaf9;
          }
          .brand span {
            color: #f59e0b;
          }
          .tagline {
            font-size: 11px;
            font-weight: 500;
            color: #78716c;
            letter-spacing: 0.12em;
            margin-bottom: 4px;
          }
          .tagline:last-of-type {
            margin-bottom: 24px;
          }
          .loading-wrap {
            display: flex;
            align-items: center;
            gap: 10px;
          }
          .spinner {
            width: 16px;
            height: 16px;
            border-radius: 50%;
            border: 2px solid rgba(245, 158, 11, 0.25);
            border-top-color: #f59e0b;
            animation: spin 0.8s linear infinite;
          }
          .status {
            font-size: 13px;
            font-weight: 500;
            color: #a8a29e;
          }
          @keyframes spin { to { transform: rotate(360deg); } }
        </style>
      </head>
      <body>
        <div class="logo-circle" aria-hidden="true">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10"/>
            <circle cx="12" cy="12" r="3"/>
          </svg>
        </div>
        <div class="brand">Crate<span>Bot</span></div>
        <div class="tagline">GENRE - TIMING - MOOD - DESCRIPTION</div>
        <div class="tagline">YOUR TAGGING BUDDY</div>
        <div class="loading-wrap">
          <div class="spinner"></div>
          <div class="status" id="status">Starting up...</div>
        </div>
        <script>
          (function () {
            var statuses = [
              'Starting up...',
              'Loading interface...',
              'Connecting to server...',
              'Loading models...'
            ]
            var index = 0
            var el = document.getElementById('status')
            setInterval(function () {
              index = (index + 1) % statuses.length
              if (el) el.textContent = statuses[index]
            }, 1200)
          })()
        </script>
      </body>
    </html>
  `

  splashWindow = new BrowserWindow({
    width: 320,
    height: 280,
    resizable: false,
    movable: true,
    frame: false,
    transparent: false,
    show: false,
    alwaysOnTop: true,
    backgroundColor: '#1a1918',
  })

  splashWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(splashHtml)}`)
  splashWindow.once('ready-to-show', () => {
    splashWindow?.show()
  })

  splashWindow.on('closed', () => {
    splashWindow = null
  })
}

/**
 * Create the main application window
 */
function createWindow() {
  logMain('Creating main window')
  // In production, preload.js is unpacked from asar to app.asar.unpacked/
  const preloadPath = isDev
    ? path.join(__dirname, 'preload.js')
    : path.join(process.resourcesPath, 'app.asar.unpacked', 'dist-electron', 'preload.js')

  console.log('Preload path:', preloadPath)
  console.log('Preload exists:', fs.existsSync(preloadPath))

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    show: false,
    backgroundColor: '#0f172a',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: preloadPath,
    },
  })

  // Load the app
  if (isDev) {
    mainWindow.loadURL('http://localhost:5173')
    mainWindow.webContents.openDevTools()
  } else {
    mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'))
  }

  mainWindow.webContents.on('render-process-gone', (_, details) => {
    logMain(`Renderer process gone: reason=${details.reason} exitCode=${details.exitCode}`)
  })

  mainWindow.webContents.on('console-message', (_event, level, message, line, sourceId) => {
    const levelName = ['debug', 'info', 'warn', 'error'][level] || `level-${level}`
    logMain(`Renderer console ${levelName}: ${message} (${sourceId}:${line})`)
  })

  mainWindow.webContents.on('did-fail-load', (_, errorCode, errorDescription, validatedURL) => {
    logMain(`did-fail-load: code=${errorCode} desc=${errorDescription} url=${validatedURL}`)
  })

  mainWindow.webContents.on('did-fail-provisional-load', (_, errorCode, errorDescription, validatedURL) => {
    logMain(`did-fail-provisional-load: code=${errorCode} desc=${errorDescription} url=${validatedURL}`)
  })

  mainWindow.on('closed', () => {
    logMain('Main window closed')
    mainWindow = null
  })

  mainWindow.once('ready-to-show', () => {
    if (!mainWindow) return
    logMain('Main window ready-to-show')
    mainWindow.show()
    if (splashWindow) {
      splashWindow.close()
      splashWindow = null
    }
  })
}

// =============================================================================
// IPC Handlers
// =============================================================================

// File dialogs
ipcMain.handle('dialog:openDirectory', async () => {
  if (!mainWindow) {
    console.error('dialog:openDirectory called but mainWindow is null')
    return null
  }
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
  })
  return result.canceled ? null : result.filePaths[0]
})

ipcMain.handle('dialog:openFiles', async (_, options?: { filters?: Electron.FileFilter[] }) => {
  if (!mainWindow) {
    console.error('dialog:openFiles called but mainWindow is null')
    return []
  }
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openFile', 'multiSelections', 'openDirectory'],
    filters: options?.filters || [
      { name: 'MP3 Files', extensions: ['mp3'] },
      { name: 'All Files', extensions: ['*'] },
    ],
  })
  return result.canceled ? [] : result.filePaths
})

ipcMain.handle('dialog:saveFile', async (_, options?: { defaultPath?: string; filters?: Electron.FileFilter[] }) => {
  if (!mainWindow) {
    console.error('dialog:saveFile called but mainWindow is null')
    return null
  }
  const result = await dialog.showSaveDialog(mainWindow, {
    defaultPath: options?.defaultPath,
    filters: options?.filters || [
      { name: 'Model Files', extensions: ['pkl'] },
    ],
  })
  return result.canceled ? null : result.filePath
})

// Shell operations
ipcMain.handle('shell:openExternal', async (_, url: string) => {
  await shell.openExternal(url)
})

ipcMain.handle('shell:showItemInFolder', async (_, path: string) => {
  shell.showItemInFolder(path)
})

// Python server status
ipcMain.handle('python:isRunning', () => {
  return pythonProcess !== null && pythonProcess.exitCode === null
})

ipcMain.handle('python:restart', async () => {
  stopPythonServer()
  await startPythonServer()
  return true
})

// Bundled model path resolution
ipcMain.handle('model:getBundledPath', () => {
  const modelName = 'cratebot-default.pkl'
  const modelPath = isDev
    ? path.join(__dirname, '..', 'resources', 'models', modelName)
    : path.join(process.resourcesPath, 'models', modelName)

  // Check if model exists
  if (fs.existsSync(modelPath)) {
    return modelPath
  }
  return null
})

// App info
ipcMain.handle('app:getVersion', () => app.getVersion())
ipcMain.handle('app:getPaths', () => ({
  home: app.getPath('home'),
  userData: app.getPath('userData'),
  temp: app.getPath('temp'),
}))

// Update handlers
ipcMain.handle('app:checkForUpdates', async () => {
  try {
    const result = await autoUpdater.checkForUpdates()
    return result?.updateInfo
  } catch (error) {
    console.error('Update check failed:', error)
    return null
  }
})

ipcMain.handle('app:downloadUpdate', async () => {
  try {
    await autoUpdater.downloadUpdate()
    return true
  } catch (error) {
    console.error('Update download failed:', error)
    return false
  }
})

ipcMain.handle('app:installUpdate', () => {
  autoUpdater.quitAndInstall()
})

// =============================================================================
// Auto-Updater Events
// =============================================================================

function setupAutoUpdater() {
  autoUpdater.on('checking-for-update', () => {
    console.log('Checking for updates...')
  })

  autoUpdater.on('update-available', (info) => {
    console.log('Update available:', info.version)
    mainWindow?.webContents.send('update:available', info)
  })

  autoUpdater.on('update-not-available', () => {
    console.log('No updates available')
  })

  autoUpdater.on('download-progress', (progress) => {
    mainWindow?.webContents.send('update:progress', progress)
  })

  autoUpdater.on('update-downloaded', (info) => {
    console.log('Update downloaded:', info.version)
    mainWindow?.webContents.send('update:downloaded', info)

    // Show dialog asking to restart
    dialog
      .showMessageBox(mainWindow!, {
        type: 'info',
        title: 'Update Ready',
        message: `Version ${info.version} has been downloaded.`,
        detail: 'The update will be installed when you restart the app.',
        buttons: ['Restart Now', 'Later'],
        defaultId: 0,
      })
      .then((result) => {
        if (result.response === 0) {
          autoUpdater.quitAndInstall()
        }
      })
  })

  autoUpdater.on('error', (error) => {
    console.error('Auto-updater error:', error)
  })
}

// =============================================================================
// Application Menu with Keyboard Shortcuts
// =============================================================================

function createMenu() {
  const isMac = process.platform === 'darwin'

  const template: Electron.MenuItemConstructorOptions[] = [
    // App Menu (macOS only)
    ...(isMac
      ? [
          {
            label: app.name,
            submenu: [
              { role: 'about' as const },
              { type: 'separator' as const },
              {
                label: 'Check for Updates...',
                click: () => autoUpdater.checkForUpdates(),
              },
              { type: 'separator' as const },
              {
                label: 'Settings',
                accelerator: 'CmdOrCtrl+,',
                click: () => mainWindow?.webContents.send('navigate', 'settings'),
              },
              { type: 'separator' as const },
              { role: 'services' as const },
              { type: 'separator' as const },
              { role: 'hide' as const },
              { role: 'hideOthers' as const },
              { role: 'unhide' as const },
              { type: 'separator' as const },
              { role: 'quit' as const },
            ],
          } as Electron.MenuItemConstructorOptions,
        ]
      : []),

    // File Menu
    {
      label: 'File',
      submenu: [
        {
          label: 'Open Directory...',
          accelerator: 'CmdOrCtrl+O',
          click: async () => {
            const result = await dialog.showOpenDialog(mainWindow!, {
              properties: ['openDirectory'],
            })
            if (!result.canceled && result.filePaths[0]) {
              mainWindow?.webContents.send('file:openDirectory', result.filePaths[0])
            }
          },
        },
        { type: 'separator' },
        isMac ? { role: 'close' } : { role: 'quit' },
      ],
    },

    // Edit Menu
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },

    // View Menu
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { type: 'separator' },
        {
          label: 'Toggle Dark Mode',
          accelerator: 'CmdOrCtrl+Shift+D',
          click: () => mainWindow?.webContents.send('theme:toggle'),
        },
      ],
    },

    // Go Menu (Tab Navigation)
    {
      label: 'Go',
      submenu: [
        {
          label: 'Train',
          accelerator: 'CmdOrCtrl+1',
          click: () => mainWindow?.webContents.send('navigate', 'train'),
        },
        {
          label: 'Tag',
          accelerator: 'CmdOrCtrl+2',
          click: () => mainWindow?.webContents.send('navigate', 'tag'),
        },
        {
          label: 'Refine',
          accelerator: 'CmdOrCtrl+3',
          click: () => mainWindow?.webContents.send('navigate', 'refine'),
        },
        {
          label: 'Settings',
          accelerator: 'CmdOrCtrl+4',
          click: () => mainWindow?.webContents.send('navigate', 'settings'),
        },
      ],
    },

    // Window Menu
    {
      label: 'Window',
      submenu: [
        { role: 'minimize' },
        { role: 'zoom' },
        ...(isMac
          ? [
              { type: 'separator' as const },
              { role: 'front' as const },
            ]
          : [{ role: 'close' as const }]),
      ],
    },

    // Help Menu
    {
      label: 'Help',
      submenu: [
        {
          label: 'Documentation',
          click: () => shell.openExternal('https://github.com/your-org/cratebot#readme'),
        },
        {
          label: 'Report Issue',
          click: () => shell.openExternal('https://github.com/your-org/cratebot/issues'),
        },
      ],
    },
  ]

  const menu = Menu.buildFromTemplate(template)
  Menu.setApplicationMenu(menu)
}

// =============================================================================
// App Lifecycle
// =============================================================================

process.on('uncaughtException', (error) => {
  logMain(`uncaughtException: ${error?.stack || error}`)
})

process.on('unhandledRejection', (reason) => {
  logMain(`unhandledRejection: ${String(reason)}`)
})

app.on('render-process-gone', (_, webContents, details) => {
  logMain(`App render-process-gone: reason=${details.reason} exitCode=${details.exitCode} url=${webContents.getURL()}`)
})

app.on('child-process-gone', (_, details) => {
  logMain(`Child process gone: type=${details.type} reason=${details.reason} exitCode=${details.exitCode} name=${details.name || 'unknown'}`)
})

app.whenReady().then(async () => {
  if (!appLogPath) {
    const logDir = path.join(app.getPath('userData'), 'logs')
    fs.mkdirSync(logDir, { recursive: true })
    appLogPath = path.join(logDir, 'cratebot-electron.log')
    fs.writeFileSync(appLogPath, '')
    logMain('Electron log initialized')
  }

  // Register cratebot:// protocol for audio file access
  registerProtocol()

  // Set up auto-updater
  setupAutoUpdater()

  // Create application menu with keyboard shortcuts
  createMenu()

  // Show splash screen immediately
  createSplashWindow()

  // Start Python server first
  try {
    await startPythonServer()
  } catch (error) {
    console.error('Failed to start Python server:', error)
    // Continue anyway, UI will show error
  }

  createWindow()

  // Check for updates after window is ready (in production only)
  if (app.isPackaged) {
    setTimeout(() => {
      autoUpdater.checkForUpdates()
    }, 3000)
  }

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow()
    }
  })
})

app.on('window-all-closed', () => {
  stopPythonServer()
  if (process.platform !== 'darwin') {
    app.quit()
  }
})

app.on('before-quit', () => {
  stopPythonServer()
})
