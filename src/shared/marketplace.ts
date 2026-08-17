export type MarketplaceKind = 'plugins' | 'skins'

export interface MarketplaceRepository {
  id: number
  fullName: string
  name: string
  owner: string
  description: string | null
  htmlUrl: string
  topics: string[]
  stars: number
  forks: number
  openIssues: number
  language: string | null
  license: string | null
  updatedAt: string
  defaultBranch: string
  archived: boolean
  fork: boolean
}

export interface MarketplaceResult {
  totalCount: number
  incompleteResults: boolean
  repositories: MarketplaceRepository[]
}

export interface MarketplacePluginPackage {
  directory: string
  name: string
  description: string | null
  skinLike: boolean
}

export class MarketplaceError extends Error {}

const MARKETPLACE_QUERIES: Record<MarketplaceKind, string> = {
  plugins: 'dsh plugin in:topics',
  skins: 'dsh skin in:topics'
}

export function marketplaceQuery(kind: MarketplaceKind): string {
  return MARKETPLACE_QUERIES[kind]
}

export function parseMarketplaceResponse(payload: unknown): MarketplaceResult {
  const root = asRecord(payload)
  if (!root) return { totalCount: 0, incompleteResults: false, repositories: [] }
  const rawItems = Array.isArray(root.items) ? root.items : []
  return {
    totalCount: asNumber(root.total_count),
    incompleteResults: root.incomplete_results === true,
    repositories: rawItems.map(normalizeRepository).filter((repository): repository is MarketplaceRepository => repository !== null)
  }
}

export function normalizeRepository(value: unknown): MarketplaceRepository | null {
  const item = asRecord(value)
  const owner = asRecord(item?.owner)
  const fullName = asString(item?.full_name)
  const htmlUrl = asString(item?.html_url)
  if (!item || !fullName || !htmlUrl) return null

  return {
    id: asNumber(item.id),
    fullName,
    name: asString(item.name) || fullName.split('/').at(-1) || fullName,
    owner: asString(owner?.login) || fullName.split('/')[0] || 'unknown',
    description: asNullableString(item.description),
    htmlUrl,
    topics: Array.isArray(item.topics) ? item.topics.filter((topic): topic is string => typeof topic === 'string') : [],
    stars: asNumber(item.stargazers_count),
    forks: asNumber(item.forks_count),
    openIssues: asNumber(item.open_issues_count),
    language: asNullableString(item.language),
    license: asNullableString(asRecord(item.license)?.spdx_id),
    updatedAt: asString(item.updated_at),
    defaultBranch: asString(item.default_branch) || 'main',
    archived: item.archived === true,
    fork: item.fork === true
  }
}

export async function fetchMarketplaceRepositories(
  kind: MarketplaceKind,
  page = 1,
  signal?: AbortSignal
): Promise<MarketplaceResult> {
  const url = new URL('https://api.github.com/search/repositories')
  url.searchParams.set('q', marketplaceQuery(kind))
  url.searchParams.set('sort', 'updated')
  url.searchParams.set('order', 'desc')
  url.searchParams.set('per_page', '30')
  url.searchParams.set('page', String(page))

  let response: Response
  try {
    response = await fetch(url, {
      signal,
      headers: { Accept: 'application/vnd.github+json' }
    })
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error
    throw new MarketplaceError('无法连接 GitHub，请检查网络后重试')
  }

  if (!response.ok) {
    if (response.status === 403 || response.status === 429) {
      throw new MarketplaceError('GitHub API 请求频率已达到限制，请稍后再试')
    }
    throw new MarketplaceError(`GitHub 返回错误（HTTP ${response.status}）`)
  }
  return parseMarketplaceResponse(await response.json())
}

/**
 * Resolves a GitHub repository to the actual dsh package. Some community
 * projects are monorepos whose root package is only an aggregator.
 */
export async function resolveMarketplaceInstallSpec(
  repository: MarketplaceRepository,
  kind: MarketplaceKind,
  signal?: AbortSignal
): Promise<string> {
  const rootManifest = await fetchJson(rawFileUrl(repository, 'package.json'), signal, true)
  if (isDshPackage(rootManifest)) return repository.fullName

  const branch = encodeURIComponent(repository.defaultBranch).replace(/%2F/g, '/')
  const tree = await fetchJson(
    `https://api.github.com/repos/${repository.fullName}/git/trees/${branch}?recursive=1`,
    signal,
    false
  )
  const paths = Array.isArray(tree?.tree)
    ? tree.tree
        .map((entry) => asString(asRecord(entry)?.path))
        .filter((path) => path.endsWith('/package.json') || path === 'package.json')
        .filter((path) => !path.split('/').some((part) => ['node_modules', 'dist', 'lib', '.git'].includes(part)))
        .slice(0, 40)
    : []
  const candidates = (
    await Promise.all(
      paths.map(async (path) => {
        const manifest = await fetchJson(rawFileUrl(repository, path), signal, true)
        return normalizePluginPackage(manifest, packageDirectory(path))
      })
    )
  ).filter((candidate): candidate is MarketplacePluginPackage => candidate !== null)
  const selected = selectMarketplacePackage(candidates, kind)
  if (selected) return `${repository.fullName}#path:/${selected.directory}`
  if (kind === 'skins') {
    throw new MarketplaceError('这个仓库没有找到可加载的 dsh 皮肤包，请查看项目说明')
  }
  return repository.fullName
}

export function selectMarketplacePackage(
  candidates: MarketplacePluginPackage[],
  kind: MarketplaceKind
): MarketplacePluginPackage | null {
  if (candidates.length === 0) return null
  return candidates.reduce((best, candidate) =>
    packageScore(candidate, kind) > packageScore(best, kind) ? candidate : best
  )
}

function packageScore(candidate: MarketplacePluginPackage, kind: MarketplaceKind): number {
  const value = `${candidate.name} ${candidate.directory} ${candidate.description ?? ''}`.toLowerCase()
  let score = candidate.directory ? 1 : 0
  if (kind === 'skins') {
    if (candidate.skinLike) score += 50
    if (candidate.directory) score += 20
    if (value.includes('skin')) score += 10
    if (value.includes('theme')) score += 6
    if (value.includes('ui')) score += 2
  }
  return score
}

function normalizePluginPackage(value: unknown, directory: string): MarketplacePluginPackage | null {
  const manifest = asRecord(value)
  if (!manifest || !isDshPackage(manifest)) return null
  const name = asString(manifest.name)
  if (!name) return null
  const valueText = `${name} ${directory} ${asString(manifest.description)}`.toLowerCase()
  return {
    directory,
    name,
    description: asNullableString(manifest.description),
    skinLike: valueText.includes('skin') || valueText.includes('theme')
  }
}

function isDshPackage(value: Record<string, unknown> | null): boolean {
  const dsh = asRecord(value?.dsh)
  return Boolean(dsh && (dsh.bundle || dsh.client))
}

function packageDirectory(path: string): string {
  return path === 'package.json' ? '' : path.slice(0, -'/package.json'.length)
}

function rawFileUrl(repository: MarketplaceRepository, path: string): string {
  const branch = encodeURIComponent(repository.defaultBranch).replace(/%2F/g, '/')
  return `https://raw.githubusercontent.com/${repository.fullName}/${branch}/${path}`
}

async function fetchJson(url: string, signal: AbortSignal | undefined, optional: boolean): Promise<Record<string, unknown> | null> {
  let response: Response
  try {
    response = await fetch(url, {
      signal,
      headers: { Accept: 'application/vnd.github+json' }
    })
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error
    throw new MarketplaceError('无法读取 GitHub 插件清单，请检查网络后重试')
  }
  if (optional && response.status === 404) return null
  if (!response.ok) throw new MarketplaceError(`GitHub 返回错误（HTTP ${response.status}）`)
  return asRecord(await response.json())
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : null
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

function asNullableString(value: unknown): string | null {
  const result = asString(value)
  return result || null
}

function asNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0
}
