import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  fetchMarketplaceRepositories,
  marketplaceQuery,
  normalizeRepository,
  parseMarketplaceResponse,
  resolveMarketplaceInstallSpec,
  selectMarketplacePackage
} from '@shared/marketplace'

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('marketplace parser', () => {
  it('uses dsh topic queries for plugins and skins', () => {
    expect(marketplaceQuery('plugins')).toBe('dsh plugin in:topics')
    expect(marketplaceQuery('skins')).toBe('dsh skin in:topics')
  })

  it('normalizes GitHub repository metadata', () => {
    const repository = normalizeRepository({
      id: 42,
      full_name: 'example/dsh-theme',
      name: 'dsh-theme',
      owner: { login: 'example' },
      html_url: 'https://github.com/example/dsh-theme',
      description: 'A theme',
      topics: ['dsh', 'skin'],
      stargazers_count: 12,
      forks_count: 3,
      open_issues_count: 1,
      language: 'TypeScript',
      license: { spdx_id: 'MIT' },
      updated_at: '2026-08-17T00:00:00Z',
      default_branch: 'main',
      archived: false,
      fork: false
    })

    expect(repository).toMatchObject({
      id: 42,
      fullName: 'example/dsh-theme',
      owner: 'example',
      stars: 12,
      license: 'MIT'
    })
  })

  it('drops malformed items and keeps the API result shape', () => {
    const result = parseMarketplaceResponse({
      total_count: 2,
      incomplete_results: true,
      items: [{ full_name: 'ok/repo', html_url: 'https://github.com/ok/repo' }, { name: 'missing-url' }]
    })

    expect(result.totalCount).toBe(2)
    expect(result.incompleteResults).toBe(true)
    expect(result.repositories).toHaveLength(1)
    expect(result.repositories[0].fullName).toBe('ok/repo')
  })

  it('requests the GitHub search endpoint with the selected topic query', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ total_count: 0, items: [] }), { status: 200 })
    )
    vi.stubGlobal('fetch', fetchMock)

    await fetchMarketplaceRepositories('skins')

    const request = fetchMock.mock.calls[0][0] as URL
    expect(request.searchParams.get('q')).toBe('dsh skin in:topics')
    expect(request.searchParams.get('per_page')).toBe('30')
  })

  it('selects the skin package inside a monorepo', () => {
    const selected = selectMarketplacePackage(
      [
        { directory: '', name: 'skin-suite', description: 'workspace root', skinLike: true },
        { directory: 'packages/dsh-pet', name: 'dsh-pet', description: 'desktop pet', skinLike: false },
        { directory: 'packages/dsh-skin-shalom', name: 'dsh-skin-shalom', description: 'web skin', skinLike: true }
      ],
      'skins'
    )
    expect(selected?.directory).toBe('packages/dsh-skin-shalom')
  })

  it('resolves a GitHub monorepo skin to pnpm path syntax', async () => {
    const repository = normalizeRepository({
      id: 7,
      full_name: 'youngiry/shalom-dsh',
      html_url: 'https://github.com/youngiry/shalom-dsh',
      default_branch: 'main'
    })!
    const fetchMock = vi.fn().mockImplementation(async (input: URL) => {
      const url = String(input)
      if (url.includes('/git/trees/')) {
        return new Response(JSON.stringify({ tree: [
          { path: 'package.json' },
          { path: 'packages/dsh-skin-shalom/package.json' },
          { path: 'packages/dsh-pet-shalom/package.json' }
        ] }), { status: 200 })
      }
      if (url.includes('dsh-skin-shalom')) {
        return new Response(JSON.stringify({
          name: 'dsh-skin-shalom',
          description: 'web skin',
          dsh: { bundle: { patch: './cordis.patch.yml' }, client: { platform: 'web' } }
        }), { status: 200 })
      }
      if (url.includes('dsh-pet-shalom')) {
        return new Response(JSON.stringify({
          name: 'dsh-pet-shalom',
          description: 'desktop pet',
          dsh: { bundle: { patch: './cordis.patch.yml' }, client: { platform: 'web' } }
        }), { status: 200 })
      }
      return new Response(JSON.stringify({ name: 'shalom-dsh', private: true }), { status: 200 })
    })
    vi.stubGlobal('fetch', fetchMock)

    await expect(resolveMarketplaceInstallSpec(repository, 'skins')).resolves.toBe(
      'youngiry/shalom-dsh#path:/packages/dsh-skin-shalom'
    )
  })
})
