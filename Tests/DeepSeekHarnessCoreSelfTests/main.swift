import DeepSeekHarnessCore
import Darwin

var failures = 0

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("PASS  \(message)")
    } else {
        failures += 1
        print("FAIL  \(message)")
    }
}

func expectThrows(_ message: String, _ block: () throws -> Void) {
    do {
        try block()
        failures += 1
        print("FAIL  \(message) (未抛出错误)")
    } catch {
        print("PASS  \(message)")
    }
}

// GitHub 地址规范化
do {
    let a = try GitHubSpecParser.parse("deepseek-ai/deepseek-harness")
    expect(a.owner == "deepseek-ai" && a.repository == "deepseek-harness", "owner/repo")
    expect(a.ref == nil && a.pnpmArgument == "github:deepseek-ai/deepseek-harness", "owner/repo → github: spec")

    let b = try GitHubSpecParser.parse("some-user/my-plugin#v1.2.0")
    expect(b.ref == "v1.2.0" && b.pnpmArgument == "github:some-user/my-plugin#v1.2.0", "owner/repo#ref")

    let c = try GitHubSpecParser.parse("https://github.com/deepseek-ai/deepseek-harness")
    expect(c.pnpmArgument == "github:deepseek-ai/deepseek-harness", "https URL")

    let d = try GitHubSpecParser.parse("https://github.com/some-user/my-plugin.git#main")
    expect(d.owner == "some-user" && d.repository == "my-plugin" && d.ref == "main", "https + .git + #ref")

    let e = try GitHubSpecParser.parse("https://github.com/some-user/my-plugin/tree/next/sub/dir")
    expect(e.ref == "next/sub/dir", "https tree 路径提取 ref")

    let f = try GitHubSpecParser.parse("git+https://github.com/some-user/my-plugin.git")
    expect(f.pnpmArgument == "github:some-user/my-plugin", "git+https")

    let g = try GitHubSpecParser.parse("git@github.com:some-user/my-plugin.git")
    expect(g.pnpmArgument == "github:some-user/my-plugin", "git@ scp 风格")

    expectThrows("空输入") { _ = try GitHubSpecParser.parse("") }
    expectThrows("非仓库输入") { _ = try GitHubSpecParser.parse("not-a-repo") }
    expectThrows("非 GitHub 主机") { _ = try GitHubSpecParser.parse("https://gitlab.com/owner/repo") }
}

// ZIP 目录定位
do {
    expect(ArchivePackageLocator.packageRootRelativePath(entries: ["package.json", "src/index.js"]) == "", "ZIP 根目录 package.json")
    expect(ArchivePackageLocator.packageRootRelativePath(entries: ["my-plugin/package.json", "my-plugin/src/index.js"]) == "my-plugin", "ZIP 唯一顶层目录")
    expect(ArchivePackageLocator.packageRootRelativePath(entries: ["__MACOSX/foo", "my-plugin/package.json"]) == "my-plugin", "忽略 __MACOSX")
    expect(ArchivePackageLocator.packageRootRelativePath(entries: ["a/package.json", "b/package.json"]) == nil, "歧义 ZIP 拒绝")
    expect(ArchivePackageLocator.packageRootRelativePath(entries: ["src/index.js"]) == nil, "缺少 package.json 拒绝")
}

// dsh web 输出解析
do {
    let url = WebServerManager.urlFromOutput("dsh web: http://127.0.0.1:54288")
    expect(url?.absoluteString == "http://127.0.0.1:54288" && url?.port == 54288, "解析 127.0.0.1 URL")
    let local = WebServerManager.urlFromOutput("listening at http://localhost:3080/")
    expect(local?.port == 3080, "解析 localhost URL")
    expect(WebServerManager.urlFromOutput("some random stdout") == nil, "忽略无关输出")
}

if failures == 0 {
    print("ALL TESTS PASSED")
} else {
    print("\(failures) TEST(S) FAILED")
    exit(1)
}
