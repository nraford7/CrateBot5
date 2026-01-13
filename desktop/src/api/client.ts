/**
 * CrateBot API Client
 * Communicates with the Python FastAPI backend
 */

const API_BASES = [
  import.meta.env.VITE_API_BASE,
  'http://127.0.0.1:8742',
  'http://localhost:8742',
].filter(Boolean) as string[]

let activeBase = API_BASES[0]

const getWebSocketBase = (httpBase: string) =>
  httpBase.replace(/^http:/, 'ws:').replace(/^https:/, 'wss:')

class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
    this.name = 'ApiError'
  }
}

async function request<T>(
  endpoint: string,
  options: RequestInit = {}
): Promise<T> {
  let lastError: unknown

  for (const base of API_BASES) {
    const url = `${base}${endpoint}`
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      })

      if (!response.ok) {
        const errorText = await response.text()
        throw new ApiError(response.status, errorText)
      }

      activeBase = base
      return response.json()
    } catch (error) {
      if (error instanceof ApiError) {
        throw error
      }
      lastError = error
    }
  }

  throw lastError instanceof Error ? lastError : new Error('Request failed')
}

// API Types
interface HealthResponse {
  status: string
  model_loaded: boolean
  tag_manager_ready: boolean
}

interface ModelInfo {
  loaded: boolean
  path?: string
  name?: string
  selected_tags?: {
    genre: string[]
    timing: string[]
    mood: string[]
    descriptive: string[]
  }
}

interface Settings {
  anthropic_api_key_set: boolean
  models_directory: string
  cache_directory: string
  vibe_available: boolean
  vibe_status: string
  hook_available: boolean
  hook_status: string
  panns_available: boolean
}

interface TaggingResult {
  file_path: string
  filename: string
  status: 'tagged' | 'review' | 'skipped' | 'failed'
  predicted_tags?: {
    genre?: string
    album?: string
    comments?: string
    mood?: string
  }
  vibe?: string
  description?: string
  hook?: string
  error?: string
}

interface TaskResponse {
  task_id: string
  status: string
  total_files?: number
}

interface TaskStatus {
  task_id: string
  task_type: string
  status: string
  progress: number
  phase: string
  current_item?: string
  current_index: number
  total_items: number
  message?: string
  result?: unknown
  error?: string
}

interface FileItem {
  name: string
  path: string
  is_dir: boolean
  size_bytes?: number
  extension?: string
}

interface BrowseResponse {
  path: string
  parent: string
  items: FileItem[]
}

interface Mp3Response {
  directory: string
  files: Array<{ path: string; name: string; size_bytes: number }>
  count: number
}

interface Tags {
  [key: string]: unknown
}

export interface LexiconCategory {
  id3_frame: string
  mappings: Record<string, string>
}

export interface LexiconConfig {
  categories: {
    genre: LexiconCategory
    timing: LexiconCategory
    mood: LexiconCategory
    descriptive: LexiconCategory
  }
}

export interface LexiconUpdate {
  category: string
  id3_frame?: string
  mappings?: Record<string, string>
}

export interface OverrideResponse {
  has_override: boolean
  tags: Record<string, any> | null
  hash: string
}

// API Client
export const api = {
  getApiBases: () => [...API_BASES],
  getActiveBase: () => activeBase,
  // Health
  health: () => request<HealthResponse>('/api/v1/health'),

  // Settings
  getSettings: () => request<Settings>('/api/v1/settings'),
  setApiKey: (apiKey: string) =>
    request('/api/v1/settings/api-key', {
      method: 'POST',
      body: JSON.stringify({ api_key: apiKey }),
    }),

  // Model
  getModelInfo: () => request<ModelInfo>('/api/v1/model/info'),
  loadModel: async (modelPath: string) => {
    // Resolve bundled:// protocol to actual file path
    let resolvedPath = modelPath
    if (modelPath.startsWith('bundled://')) {
      if (typeof window !== 'undefined' && window.electron?.model) {
        const bundledPath = await window.electron.model.getBundledPath()
        if (bundledPath) {
          resolvedPath = bundledPath
        } else {
          throw new Error('Bundled model not found. Please load a custom model.')
        }
      } else {
        throw new Error('Bundled model not available in this environment.')
      }
    }
    return request('/api/v1/model/load', {
      method: 'POST',
      body: JSON.stringify({ model_path: resolvedPath }),
    })
  },
  listModels: () => request<{ models: Array<{ name: string; path: string; size_bytes: number; modified_at: string }> }>('/api/v1/model/list'),

  // Training
  startTraining: (params: {
    training_dir: string
    output_model_path: string
    selected_tags: { genre: string[]; timing: string[]; mood: string[]; descriptive: string[] }
    test_size?: number
    tag_sources?: { genre_frame?: string; timing_frame?: string; mood_frame?: string; comments_frame?: string }
  }) =>
    request<TaskResponse>('/api/v1/train/start', {
      method: 'POST',
      body: JSON.stringify(params),
    }),
  getTrainingStatus: (taskId: string) =>
    request<TaskStatus>(`/api/v1/train/status/${taskId}`),
  cancelTraining: (taskId: string) =>
    request(`/api/v1/train/cancel/${taskId}`, { method: 'POST' }),

  // Tagging
  tagFile: (params: {
    file_path: string
    overwrite?: boolean
    dry_run?: boolean
    tags_to_write?: { genre: boolean; album: boolean; comments: boolean; mood: boolean; likeness: boolean }
  }) =>
    request<TaggingResult>('/api/v1/tag/file', {
      method: 'POST',
      body: JSON.stringify(params),
    }),
  tagBatch: (params: {
    file_paths: string[]
    overwrite?: boolean
    dry_run?: boolean
    tags_to_write?: { genre: boolean; album: boolean; comments: boolean; mood: boolean; likeness: boolean }
    generate_vibes?: boolean
    generate_hooks?: boolean
  }) =>
    request<TaskResponse>('/api/v1/tag/batch', {
      method: 'POST',
      body: JSON.stringify(params),
    }),
  cancelTagging: (taskId: string) =>
    request(`/api/v1/tag/cancel/${taskId}`, { method: 'POST' }),

  // Vibe
  generateVibe: (params: {
    file_path: string
    overwrite?: boolean
    dry_run?: boolean
    skip_hook?: boolean
  }) =>
    request('/api/v1/vibe/file', {
      method: 'POST',
      body: JSON.stringify(params),
    }),
  generateVibeBatch: (params: {
    file_paths: string[]
    overwrite?: boolean
    dry_run?: boolean
    skip_hook?: boolean
  }) =>
    request<TaskResponse>('/api/v1/vibe/batch', {
      method: 'POST',
      body: JSON.stringify(params),
    }),

  // Tags
  readTags: (filePath: string) =>
    request<{ file_path: string; tags: Tags }>('/api/v1/tags/read', {
      method: 'POST',
      body: JSON.stringify({ file_path: filePath }),
    }),
  writeTags: (filePath: string, tags: Tags, overwrite = true) =>
    request('/api/v1/tags/write', {
      method: 'POST',
      body: JSON.stringify({ file_path: filePath, tags, overwrite }),
    }),

  // Tasks
  getTaskStatus: (taskId: string) => request<TaskStatus>(`/api/v1/tasks/${taskId}`),
  listTasks: (taskType?: string) =>
    request<{ tasks: TaskStatus[] }>(`/api/v1/tasks${taskType ? `?task_type=${taskType}` : ''}`),
  pauseTask: (taskId: string) =>
    request(`/api/v1/tasks/${taskId}/pause`, { method: 'POST' }),
  resumeTask: (taskId: string) =>
    request(`/api/v1/tasks/${taskId}/resume`, { method: 'POST' }),

  // Files
  browse: (path: string) => request<BrowseResponse>(`/api/v1/files/browse?path=${encodeURIComponent(path)}`),
  findMp3s: (directory: string, recursive = true) =>
    request<Mp3Response>(`/api/v1/files/mp3s?directory=${encodeURIComponent(directory)}&recursive=${recursive}`),

  // Scan
  scanTags: (directory: string, tagSources?: { genre_frame?: string; timing_frame?: string; mood_frame?: string; comments_frame?: string }) =>
    request('/api/v1/scan/tags', {
      method: 'POST',
      body: JSON.stringify({ directory, tag_sources: tagSources }),
    }),

  // Lexicon
  getLexicon: () => request<LexiconConfig>('/api/v1/lexicon'),
  updateLexicon: (update: LexiconUpdate) =>
    request<void>('/api/v1/lexicon', {
      method: 'PUT',
      body: JSON.stringify(update),
    }),

  // Override
  saveOverride: (filePath: string, tags: Record<string, any>) =>
    request<{ status: string; hash: string }>('/api/v1/override', {
      method: 'POST',
      body: JSON.stringify({ file_path: filePath, tags }),
    }),
  getOverride: (filePath: string) =>
    request<OverrideResponse>(`/api/v1/override/${encodeURIComponent(filePath)}`),
}

// WebSocket for progress updates
export function createProgressSocket(taskId: string, onMessage: (data: TaskStatus) => void) {
  const wsBase = getWebSocketBase(activeBase)
  const ws = new WebSocket(`${wsBase}/api/v1/ws/progress/${taskId}`)

  ws.onmessage = (event) => {
    if (event.data === 'heartbeat' || event.data === 'pong') return
    try {
      const data = JSON.parse(event.data)
      onMessage(data)
    } catch {
      // Ignore parse errors
    }
  }

  ws.onerror = (error) => {
    console.error('WebSocket error:', error)
  }

  // Send ping every 25 seconds to keep connection alive
  const pingInterval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send('ping')
    }
  }, 25000)

  return {
    close: () => {
      clearInterval(pingInterval)
      ws.close()
    }
  }
}
