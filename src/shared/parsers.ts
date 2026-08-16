export interface GitHubPluginSpec {
  owner: string
  repository: string
  ref: string | null
  pnpmArgument: string
  displayName: string
}

function stripDotGit(name: string): string {
  return name.toLowerCase().endsWith('.git') ? name.slice(0, -4) : name
}

function isValidName(name: string): boolean {
  return /^[A-Za-z0-9_.-]+$/.test(name) && name !== '.' && name !== '..'
}

function parseGitHubPath(urlString: string): string | null {
  const withoutProtocol = urlString
    .replace(/^https:\/\//, '')
    .replace(/^http:\/\//, '')
    .replace(/^git\+/, '')
    .replace(/^ssh:\/\//, '')
    .replace(/^git@/, '')
  const slash = withoutProtocol.indexOf('/')
  if (slash < 0) return null
  let path = withoutProtocol.slice(slash)
  const hash = path.indexOf('#')
  if (hash >= 0) path = path.slice(0, hash)
  const query = path.indexOf('?')
  if (query >= 0) path = path.slice(0, query)
  return path
}

export class PluginSpecError extends Error {}

export function parseGitHubSpec(rawInput: string): GitHubPluginSpec {
  const input = rawInput.trim()
  if (!input) throw new PluginSpecError('请输入 GitHub 仓库地址')

  if (input.includes('github.com')) {
    const normalized = input
      .replace(/^git\+ssh:\/\/git@github\.com\//, 'https://github.com/')
      .replace(/^ssh:\/\/git@github\.com\//, 'https://github.com/')
      .replace(/^git@github\.com:/, 'https://github.com/')
      .replace(/^git\+https:\/\/github\.com\//, 'https://github.com/')
      .replace(/^git\+ssh:\/\/github\.com\//, 'https://github.com/')

    const path = parseGitHubPath(normalized)
    let components: URL | null = null
    try {
      components = new URL(normalized)
    } catch {
      components = null
    }
    if (!path) throw new PluginSpecError(`无法解析 GitHub 仓库：${input}`)

    const pieces = path.split('/').filter(Boolean)
    if (pieces.length < 2) throw new PluginSpecError(`无法解析 GitHub 仓库：${input}`)
    let ref = components?.hash ? decodeURIComponent(components.hash.slice(1)) : null
    const repo = stripDotGit(pieces[1])
    if (pieces.length >= 4 && pieces[2].toLowerCase() === 'tree') {
      ref = pieces.slice(3).join('/')
    } else if (pieces.length > 2) {
      throw new PluginSpecError(
        `不支持的地址：${input}\n支持 owner/repo、https://github.com/owner/repo 或 git@github.com:owner/repo.git 形式`
      )
    }
    if (!isValidName(pieces[0]) || !isValidName(repo)) {
      throw new PluginSpecError(`无法解析 GitHub 仓库：${input}`)
    }
    const pnpm = `github:${pieces[0]}/${repo}${ref ? `#${ref}` : ''}`
    return { owner: pieces[0], repository: repo, ref, pnpmArgument: pnpm, displayName: `${pieces[0]}/${repo}${ref ? `@${ref}` : ''}` }
  }

  if (input.includes('/')) {
    const [pathPartRaw, fragmentRaw] = input.split('#', 2)
    const pathPart = pathPartRaw.replace(/^github:/, '')
    const pieces = pathPart.split('/').filter(Boolean)
    if (pieces.length !== 2) {
      throw new PluginSpecError(`不支持的地址：${input}\n支持 owner/repo 或 owner/repo#分支`)
    }
    const owner = pieces[0]
    const repo = stripDotGit(pieces[1])
    if (!isValidName(owner) || !isValidName(repo)) {
      throw new PluginSpecError(`无法解析 GitHub 仓库：${input}`)
    }
    const ref = fragmentRaw?.trim() || null
    const pnpm = `github:${owner}/${repo}${ref ? `#${ref}` : ''}`
    return { owner, repository: repo, ref, pnpmArgument: pnpm, displayName: `${owner}/${repo}${ref ? `@${ref}` : ''}` }
  }

  throw new PluginSpecError(
    `不支持的地址：${input}\n支持 owner/repo、https://github.com/owner/repo 或 git@github.com:owner/repo.git 形式`
  )
}

/**
 * ZIP 解包后的目录定位：package.json 在根目录或唯一的一级子目录内。
 */
export function locatePackageRoot(entries: string[]): string | null {
  const normalized = entries
    .map((entry) => entry.replace(/^\/+|\/+$/g, ''))
    .filter((entry) => entry && !entry.startsWith('__MACOSX'))

  if (normalized.includes('package.json')) return ''

  const topLevelDirectories = new Set<string>()
  for (const entry of normalized) {
    const pieces = entry.split('/')
    if (pieces.length > 1) topLevelDirectories.add(pieces[0])
  }
  if (topLevelDirectories.size === 1) {
    const only = [...topLevelDirectories][0]
    if (normalized.includes(`${only}/package.json`)) return only
  }
  return null
}

/** 解析 dsh web stdout 中的本机 URL。 */
export function parseWebURL(line: string): URL | null {
  const match = line.match(/https?:\/\/(?:127\.0\.0\.1|localhost|\[::1\]):\d{2,5}/)
  if (!match) return null
  try {
    return new URL(match[0])
  } catch {
    return null
  }
}

/** 从 InstalledPlugin 的 spec 推导来源与主页。 */
export function pluginSourceKind(spec: string): 'github' | 'zip' | 'folder' | 'npm' {
  const lower = spec.toLowerCase()
  if (lower.startsWith('file:') || lower.startsWith('link:')) return 'folder'
  if (lower.includes('github:') || lower.includes('git+') || lower.includes('git@')) return 'github'
  if (lower.startsWith('http') && lower.includes('.tgz')) return 'zip'
  return 'npm'
}

export function pluginLocalSource(spec: string): string | null {
  const lower = spec.toLowerCase()
  if (!lower.startsWith('file:') && !lower.startsWith('link:')) return null
  try {
    const url = new URL(spec)
    return decodeURIComponent(url.pathname)
  } catch {
    return null
  }
}

export function pluginExternalUrl(name: string, spec: string): string | null {
  const kind = pluginSourceKind(spec)
  if (kind === 'npm') {
    return `https://www.npmjs.com/package/${name}`
  }
  if (kind === 'github') {
    const cleaned = spec
      .replace(/^git\+https:\/\/github\.com\//, 'https://github.com/')
      .replace(/^git\+ssh:\/\/git@github\.com\//, 'https://github.com/')
      .replace(/^git@github\.com:/, 'https://github.com/')
      .replace(/^github:/, 'https://github.com/')
    try {
      const parsed = new URL(cleaned)
      const pieces = parsed.pathname.split('/').filter(Boolean)
      if (pieces.length < 2) return null
      let repo = pieces[1]
      if (repo.toLowerCase().endsWith('.git')) repo = repo.slice(0, -4)
      const base = `https://github.com/${pieces[0]}/${repo}`
      const ref = parsed.hash?.slice(1).trim()
      return ref ? `${base}/tree/${ref}` : base
    } catch {
      return null
    }
  }
  return null
}

/** 端口约束。 */
export function sanitizePort(value: number): number {
  if (!Number.isFinite(value)) return 0
  return Math.min(Math.max(Math.trunc(value), 0), 65535)
}

export function relativeTime(date: number | null): string {
  if (!date) return '时间未知'
  const diff = Date.now() - date
  const minute = 60_000
  const hour = 60 * minute
  const day = 24 * hour
  if (diff < minute) return '刚刚'
  if (diff < hour) return `${Math.floor(diff / minute)} 分钟前`
  if (diff < day) return `${Math.floor(diff / hour)} 小时前`
  if (diff < 7 * day) return `${Math.floor(diff / day)} 天前`
  return new Date(date).toLocaleDateString()
}
