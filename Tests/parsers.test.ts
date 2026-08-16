import { describe, expect, it } from 'vitest'
import {
  parseGitHubSpec,
  locatePackageRoot,
  parseWebURL,
  pluginSourceKind,
  pluginExternalUrl,
  pluginLocalSource
} from '@shared/parsers'

describe('GitHubSpecParser', () => {
  it('解析 owner/repo', () => {
    const spec = parseGitHubSpec('deepseek-ai/deepseek-harness')
    expect(spec.pnpmArgument).toBe('github:deepseek-ai/deepseek-harness')
    expect(spec.ref).toBeNull()
  })

  it('解析分支与 URL 形式', () => {
    expect(parseGitHubSpec('some-user/my-plugin#v1.2.0').pnpmArgument).toBe('github:some-user/my-plugin#v1.2.0')
    expect(parseGitHubSpec('https://github.com/deepseek-ai/deepseek-harness').pnpmArgument).toBe(
      'github:deepseek-ai/deepseek-harness'
    )
    expect(parseGitHubSpec('https://github.com/a/b.git#main').ref).toBe('main')
    expect(parseGitHubSpec('git@github.com:a/b.git').pnpmArgument).toBe('github:a/b')
  })

  it('拒绝非法输入', () => {
    expect(() => parseGitHubSpec('')).toThrow()
    expect(() => parseGitHubSpec('not-a-repo')).toThrow()
    expect(() => parseGitHubSpec('https://gitlab.com/a/b')).toThrow()
  })
})

describe('locatePackageRoot', () => {
  it('支持根目录、唯一顶层目录、忽略 __MACOSX', () => {
    expect(locatePackageRoot(['package.json', 'src/index.js'])).toBe('')
    expect(locatePackageRoot(['my-plugin/package.json', 'my-plugin/src/index.js'])).toBe('my-plugin')
    expect(locatePackageRoot(['__MACOSX/foo', 'my-plugin/package.json'])).toBe('my-plugin')
    expect(locatePackageRoot(['a/package.json', 'b/package.json'])).toBeNull()
  })
})

describe('web URL', () => {
  it('解析 dsh stdout', () => {
    expect(parseWebURL('dsh web: http://127.0.0.1:54288')?.port).toBe('54288')
    expect(parseWebURL('listening at http://localhost:3080/')?.port).toBe('3080')
    expect(parseWebURL('random text')).toBeNull()
  })
})

describe('plugin source', () => {
  it('推导来源与主页', () => {
    expect(pluginSourceKind('github:a/b#main')).toBe('github')
    expect(pluginExternalUrl('x', 'github:a/b#main')).toBe('https://github.com/a/b/tree/main')
    expect(pluginExternalUrl('@scope/pkg', '^1.2.3')).toBe('https://www.npmjs.com/package/@scope/pkg')
    expect(pluginLocalSource('file:/tmp/local-plugin')).toBe('/tmp/local-plugin')
  })
})
