---
name: pnpm-deps-upgrade
description: "在 pnpm 项目里升级依赖并安全落地:校验工作区干净且与远端同步、用 `pnx npm-check-updates` 升级(非工作区 `-u`,工作区 `-u -w`)、`pnpm clean --lockfile && pnpm i`、修复 allowBuilds 构建拦截、跑 typecheck/test、提交 `chore(deps): update deps` 并推送。只要用户提到\"升级依赖 / 更新依赖 / 升包 / 更新 package.json 里的版本 / 依赖过时 / bump deps / update dependencies\",或要求跑 `ncu`、`npm-check-updates`,即使没有明确说明提交和推送,也必须使用本 skill。"
---

# pnpm 依赖升级

把"升级依赖"从一条命令扩展成一条可回滚、可验证、可交付的流水线。用户说"升级依赖"时,真正想要的是一次干净落到远端的结果,而不是一堆改到一半的本地文件。

## 前置判断

先确认这是 pnpm 项目:根目录存在 `pnpm-lock.yaml` 或 `pnpm-workspace.yaml`,或 `package.json` 的 `packageManager` 以 `pnpm@` 开头。不是 pnpm 项目时停下,把情况告诉用户,不要自行改用 npm/yarn。

升级会改动 `package.json`、锁文件、以及被选中的依赖。所有步骤在项目根目录执行。

## 步骤

### 1. 确认工作区干净且与远端同步

```bash
git status --porcelain            # 必须为空
git fetch origin
git status -sb | head -1          # 确认与上游同步
```

- 有未提交改动:停下,把改动列给用户,让用户先 commit 或 stash。**不要**代为 stash、commit、checkout 或丢弃 —— 用户的在制品是用户的,擅自处理会丢数据。
- 落后上游:`git pull --ff-only`。快进失败(分叉)时停下问用户,不要自行 merge/rebase。
- 没有上游(本地新仓库)时,记录这一点继续,推送步骤再处理。

### 2. 判断是否工作区,再执行升级

`npm-check-updates` 的 `-w` 只接受工作区项目,加到非工作区项目上会直接失败:`workspaces property missing from package.json`。所以先用与 `soybean-cli` 的 `ncu` 命令一致的逻辑判断,再选参数:

1. `package.json` 存在 `workspaces` 字段 → 工作区(npm/yarn 格式)
2. 否则 `pnpm-workspace.yaml` 里有顶层的 `packages:` → 工作区(pnpm 格式)
3. 两者都不满足 → 非工作区

```bash
# 非工作区
pnx npm-check-updates -u

# 工作区
pnx npm-check-updates -u -w
```

一行版判断(退出码 0 = 工作区):

```bash
node -e 'const fs=require("node:fs");let ws=false;try{ws=Boolean(JSON.parse(fs.readFileSync("package.json","utf8")).workspaces)}catch{};if(!ws&&fs.existsSync("pnpm-workspace.yaml"))ws=/^packages\s*:/m.test(fs.readFileSync("pnpm-workspace.yaml","utf8"));process.exit(ws?0:1)' && echo workspace || echo single
```

- `pnx` 是 pnpm 自带的临时执行命令(等价 `pnpm dlx`),会即取即用 `npm-check-updates`,不往项目里写依赖。**不要**用 `pnpm npm-check-updates`(那是 `pnpm exec`,要求本地已装),也不要用已废弃的 `pnpx`。
- 不必去找项目自定义的 `upkg` 脚本:本 skill 自己判断工作区并直连 `npm-check-updates`,不依赖各仓库脚本的实现。仅当该项目的脚本确实携带了额外 ncu 参数(例如 `soy.config.ts` 的 `ncuCommandArgs`)时,才把这些参数一并带上。
- `-u` 会就地改写 `package.json` 的版本范围,不安装。

结束后用 `git diff --stat` 看一下实际升级了哪些包,后面写总结要用。

**非零退出时不要直接往下走**。最典型的失败原因不是升级本身,而是 ncu 改完 `package.json` 后 pnpm 顺带做的隐式安装撞上了构建脚本拦截(`ERR_PNPM_IGNORED_BUILDS`)。此时 `package.json` 可能已经改完,也可能一个字都没改。先看 `git diff --stat package.json`:

- 有改动 → 升级本身是成了,失败出在隐式安装上,按第 4 步处理 `allowBuilds` 后重跑 `pnpm i` 即可,不必重跑升级命令。
- 无改动 → 升级根本没落地,必须先按第 4 步解开构建拦截,再重跑第 2 步的升级命令。跳过这步会导致后面提交一个"没升任何依赖"的假提交。

### 3. 干净重装

```bash
pnpm clean --lockfile && pnpm i
```

删掉 `node_modules` 和锁文件后重装,是为了拿到与升级后版本区间真正一致的新解析结果。如果项目 `package.json` 自己定义了 `clean` 脚本,它会覆盖 pnpm 内建的 `pnpm clean`(pnpm 会打印 `$ ...` 说明实际执行的是脚本)。发现这种情况时,改用等价的内建行为:

```bash
rm -rf node_modules pnpm-lock.yaml && pnpm i
```

### 4. 安装报错时定位并解决

最常见的是构建脚本被拦截:

```
Error: ERR_PNPM_IGNORED_BUILDS
  × installing dependencies
  ╰─▶ Ignored build scripts: esbuild@0.21.5
```

pnpm 默认不执行依赖的 `preinstall/install/postinstall`,需要在 `pnpm-workspace.yaml` 的 `allowBuilds` 里逐包显式表态:

```yaml
allowBuilds:
  esbuild: false
```

处理规则:

- **默认 `false`**。升级依赖时引入的新构建脚本是未经审计的代码,默认拒绝执行;只有用户明确要求、或已确认该包必须跑构建才能工作时才写 `true`。
- 逐个补齐报错里列出的包,**不要**用 `dangerouslyAllowAllBuilds: true`,也**不要**用 `pnpm approve-builds --all` 图省事 —— 那等于把信任决定权交给工具。
- 项目里已有的 `allowBuilds` 条目保持原值,只增不改。
- 改完重跑 `pnpm i` 直到通过。若报错不是 `ERR_PNPM_IGNORED_BUILDS`(版本冲突、peer 冲突、完整性校验、网络/registry 等),读完整错误信息再决定;把根因和处置写进最终总结。真实冲突需要降级版本时,直接改 `package.json` 或给升级命令加 `-- <pkg>@<range>` 后重跑第 3 步。

`pnpm i` 以非零码退出即视为失败,不要跳过继续。

### 5. 跑校验(有才跑)

```bash
pnpm typecheck   # 仅当 scripts 里有
pnpm test        # 仅当 scripts 里有
```

按项目实际定义的脚本执行,不要臆造命令名。任一失败:分析原因(升级导致的 breaking change 优先怀疑),能修就修并重跑;修不动就把失败输出和判断交给用户,不要提交一个已知红的状态。

### 6. 提交并推送

先确认这次**真的升级了依赖**,而不是只装了依赖:

```bash
git diff HEAD -- package.json    # 必须能看到版本范围的变化
```

如果 `package.json` 没有任何版本变化(典型症状:第 2 步升级失败过却没重跑,提交里只有 `pnpm-lock.yaml` 和 `pnpm-workspace.yaml`),那就没有东西可提交成"依赖升级"。此时停下来回到第 2 步把升级补上,或者明确告诉用户本次没有可升级的依赖并终止 —— 不要用 `chore(deps): update deps` 记录一次没有升级的提交,那会污染历史,也让日后回溯"这个版本到底升了什么"变成考古。

确认有版本变化后再:

```bash
git add -A
git commit -m "chore(deps): update deps"
git push
```

- 提交信息固定为 `chore(deps): update deps`。
- 没有上游分支时用 `git push -u origin HEAD`。
- 推送被拒(远端有新提交)时,先 `git pull --rebase`,解决冲突后重跑第 5 步再推。
- 确认 `git status --porcelain` 为空、远端分支包含该提交。

## 汇报

结束时给用户一份简报,包含:升级涉及的包与版本变化(`git diff` 里的 `package.json` 段)、本次判断为工作区还是单包项目(即是否带 `-w`)、安装过程中解决的错误(尤其新增的 `allowBuilds` 条目及其取值理由)、typecheck/test 结果、提交哈希与推送目标分支。有跳过的步骤(没有 typecheck/test)要显式说明。

## 反例

- 未检查工作区就直接跑升级,把用户未提交的改动和升级结果混在一起。
- 工作区脏时自行 `git stash`/`git checkout .` 清场。
- 不判断工作区就统一加 `-w`,在单包项目上撞出 `workspaces property missing from package.json`。
- 用 `pnpm npm-check-updates`(要求本地已装)或已废弃的 `pnpx` 代替 `pnx`。
- 遇到 `ERR_PNPM_IGNORED_BUILDS` 就 `--all` 放行,或在 `pnpm-workspace.yaml` 里批量写 `true`。
- 升级命令因隐式安装报错而失败后,不确认 `package.json` 是否真的改过就继续,最后提交一个只装了依赖、没升版本的"假升级"提交。
- 提交前不检查 `package.json` 有无版本变化。
- typecheck/test 失败仍然提交推送。
- 把 `pnpm clean --lockfile` 与 `pnpm i` 拆成两次判断,`clean` 成功、`i` 失败却继续往下走。
