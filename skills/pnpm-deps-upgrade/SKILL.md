---
name: pnpm-deps-upgrade
description: "在 pnpm 项目里升级依赖并安全落地:校验工作区干净且与远端同步、执行 `pnpm upkg`、`pnpm clean --lockfile && pnpm i`、修复 allowBuilds 构建拦截、跑 typecheck/test、提交 `chore(deps): update deps` 并推送。只要用户提到\"升级依赖 / 更新依赖 / 升包 / 更新 package.json 里的版本 / 依赖过时 / bump deps / update dependencies\",或要求跑 `upkg`、`ncu`、`npm-check-updates`,即使没有明确说明提交和推送,也必须使用本 skill。"
---

# pnpm 依赖升级

把"升级依赖"从一条命令扩展成一条可回滚、可验证、可交付的流水线。用户说"升级依赖"时,真正想要的是一次干净落到远端的结果,而不是一堆改到一半的本地文件。

## 前置判断

先确认这是 pnpm 项目:根目录存在 `pnpm-lock.yaml` 或 `pnpm-workspace.yaml`,或 `package.json` 的 `packageManager` 以 `pnpm@` 开头。不是 pnpm 项目时停下,把情况告诉用户,不要自行改用 npm/yarn。

升级会改动 `package.json`、锁文件、以及被 `pnpm upkg` 选中升级的依赖。所有步骤在项目根目录执行。

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

### 2. 确认 `upkg` 脚本存在

读 `package.json` 的 `scripts`,找 `upkg`(SoybeanJS 项目里通常写作 `soy ncu`,即 `pnpm npm-check-updates -u [-w]`,会就地改写 `package.json` 的版本范围)。用脚本自己的值判断,而不是靠肉眼扫一眼文件:

```bash
node -p "require('./package.json').scripts?.upkg || ''"
```

输出为空 = 没有这个脚本。注意只认 `scripts.upkg` 这个键:仓库里可能存在同名的 `scripts/upkg.mjs` 文件而没有注册成脚本,那种情况下 `pnpm upkg` 依然跑不起来,同样按"没有"处理。

**没有 `upkg` 就终止任务**:告诉用户"项目未定义 `upkg` 脚本,无法继续",不要退化成手写 `pnpm update` / `ncu` / 手工改版本号,也不要直接 `node scripts/upkg.mjs` 绕过。用户的意图是走既定流程,不是随便换个方式升版本。

### 3. 执行升级

```bash
pnpm upkg
```

这一步只改 `package.json`,不安装。结束后用 `git diff --stat` 看一下实际升级了哪些包,后面写总结要用。

**`pnpm upkg` 非零退出时不要直接往下走**。最典型的失败原因不是升级本身,而是 ncu 改完 `package.json` 后 pnpm 顺带做的隐式安装撞上了构建脚本拦截(`ERR_PNPM_IGNORED_BUILDS`)。此时 `package.json` 可能已经改完,也可能一个字都没改。先看 `git diff --stat package.json`:

- 有改动 → 升级本身是成了,失败出在隐式安装上,按第 5 步处理 `allowBuilds` 后重跑 `pnpm i` 即可,不必重跑 `upkg`。
- 无改动 → 升级根本没落地,必须先按第 5 步解开构建拦截,再重跑 `pnpm upkg`。跳过这步会导致后面提交一个"没升任何依赖"的假提交。

### 4. 干净重装

```bash
pnpm clean --lockfile && pnpm i
```

删掉 `node_modules` 和锁文件后重装,是为了拿到与升级后版本区间真正一致的新解析结果。如果项目 `package.json` 自己定义了 `clean` 脚本,它会覆盖 pnpm 内建的 `pnpm clean`(pnpm 会打印 `$ ...` 说明实际执行的是脚本)。发现这种情况时,改用等价的内建行为:

```bash
rm -rf node_modules pnpm-lock.yaml && pnpm i
```

### 5. 安装报错时定位并解决

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
- 改完重跑 `pnpm i` 直到通过。若报错不是 `ERR_PNPM_IGNORED_BUILDS`(版本冲突、peer 冲突、完整性校验、网络/registry 等),读完整错误信息再决定;把根因和处置写进最终总结。真实冲突需要降级版本时,用 `pnpm upkg -- <pkg>@<range>` 或直接改 `package.json` 后重跑第 4 步。

`pnpm i` 以非零码退出即视为失败,不要跳过继续。

### 6. 跑校验(有才跑)

```bash
pnpm typecheck   # 仅当 scripts 里有
pnpm test        # 仅当 scripts 里有
```

按项目实际定义的脚本执行,不要臆造命令名。任一失败:分析原因(升级导致的 breaking change 优先怀疑),能修就修并重跑;修不动就把失败输出和判断交给用户,不要提交一个已知红的状态。

### 7. 提交并推送

先确认这次**真的升级了依赖**,而不是只装了依赖:

```bash
git diff HEAD -- package.json    # 必须能看到版本范围的变化
```

如果 `package.json` 没有任何版本变化(典型症状:第 3 步 `upkg` 失败过却没重跑,提交里只有 `pnpm-lock.yaml` 和 `pnpm-workspace.yaml`),那就没有东西可提交成"依赖升级"。此时停下来回到第 3 步把升级补上,或者明确告诉用户本次没有可升级的依赖并终止 —— 不要用 `chore(deps): update deps` 记录一次没有升级的提交,那会污染历史,也让日后回溯"这个版本到底升了什么"变成考古。

确认有版本变化后再:

```bash
git add -A
git commit -m "chore(deps): update deps"
git push
```

- 提交信息固定为 `chore(deps): update deps`。
- 没有上游分支时用 `git push -u origin HEAD`。
- 推送被拒(远端有新提交)时,先 `git pull --rebase`,解决冲突后重跑第 6 步再推。
- 确认 `git status --porcelain` 为空、远端分支包含该提交。

## 汇报

结束时给用户一份简报,包含:升级涉及的包与版本变化(`git diff` 里的 `package.json` 段)、安装过程中解决的错误(尤其新增的 `allowBuilds` 条目及其取值理由)、typecheck/test 结果、提交哈希与推送目标分支。有跳过的步骤(没有 `upkg`、没有 typecheck/test)要显式说明。

## 反例

- 未检查工作区就直接 `pnpm upkg`,把用户未提交的改动和升级结果混在一起。
- 工作区脏时自行 `git stash`/`git checkout .` 清场。
- 遇到 `ERR_PNPM_IGNORED_BUILDS` 就 `--all` 放行,或在 `pnpm-workspace.yaml` 里批量写 `true`。
- `pnpm upkg` 因隐式安装报错而失败后,不确认 `package.json` 是否真的改过就继续,最后提交一个只装了依赖、没升版本的"假升级"提交。
- 提交前不检查 `package.json` 有无版本变化。
- typecheck/test 失败仍然提交推送。
- 把 `pnpm clean --lockfile` 与 `pnpm i` 拆成两次判断,`clean` 成功、`i` 失败却继续往下走。
