---
name: soybean-standard-projects
description: "把既有前端项目(含 pnpm monorepo)迁移到 SoybeanJS 标准工程模板(ts / vue-ts 两类),用 vite-plus 取代 vite/vitest/eslint/prettier/lint-staged/husky 等分散工具。只要用户提到\"迁移到新规范 / 统一工程配置 / 项目规范化 / 按模板改造 / 换成 vite-plus / 去掉 lint-staged、simple-git-hooks、prettier、eslint / 用 soybean 标准模板\",就使用本 skill。"
---

# SoybeanJS 标准项目迁移

把已有项目对齐到 `templates/` 里的最小标准模板。核心不是"加配置",而是**用 Vite+ 的统一能力替换掉零散的旧工具链**,并删干净旧工具留下的文件、依赖和配置键。

- 本文件的相对路径全部相对本 skill 目录解析:模板在 `templates/ts/`、`templates/vue-ts/`。
- 迁移的判定基准是**模板文件本身**,不是本文档的描述。每次迁移都要逐文件读模板再落盘,不要凭记忆写。

## 适用范围

只处理两类项目(单包与 pnpm monorepo 均可),其余一律跳过并说明原因:

| 模板 | 判定依据 |
| --- | --- |
| `templates/vue-ts` | `package.json` 的 dependencies 含 `vue`,或仓库内存在 `**/*.vue` |
| `templates/ts` | 不含 vue,但存在 `tsconfig.json` 或 `src/**/*.ts`(纯 TS / Node 库 / CLI) |

**单包与 pnpm monorepo 都适用**,判定模板类型的证据规则相同:monorepo 看**主体子包**(数量最多、含 `src/App.vue` 或 root `dev` 指向的那个),而不是根目录。monorepo 的额外差异见下面「pnpm monorepo」。

直接跳过的情况:

- React / Svelte / Solid / Angular / 纯 JS 无 TS 的前端项目 —— 模板不覆盖它们的框架插件与 lint 规则。
- Nuxt / Ubean 等元框架 —— 工程结构、构建入口与服务端约定差异大,模板里没有对应物。遇到时停下问用户,不要套 `vue-ts` 模板硬改。
- 非 pnpm 的 monorepo(npm/yarn workspaces、turborepo + npm、lerna)—— 停下问用户是否愿意先换到 pnpm,不要自行更换包管理器。
- 多个子包分属不同类型(vue 与 react 混存)—— 只能迁移 `vue-ts`/`ts` 覆盖得到的子包,其余子包保持原样并在报告里说明。

## 旧工具 → Vite+ 能力对照

被替代的旧工具必须**同时**清理三处:配置文件、`package.json` 依赖、`package.json` 里的配置键。

| 旧工具 | 替代 | 需要删除的东西 |
| --- | --- | --- |
| `prettier`、`oxfmt`、`biome format` | `vp fmt`(`vite.config.ts` 的 `fmt`) | `.prettierrc*`、`prettier.config.*`、`.prettierignore`、`.oxfmtrc.json`、`biome.json`、`prettier` 依赖、`package.json#prettier` |
| `eslint`、`oxlint`、`tslint` | `vp lint`;Vue 项目另加 `eslint.config.mjs` | `.eslintrc*`、`.eslintignore`、`eslint.config.{js,cjs,ts,mjs}`(Vue 项目改为调用 `@soybeanjs/eslint-config-vue` 的新文件)、`.oxlintrc*`、`oxlint.config.*`、`tslint.json`、对应依赖 |
| `lint-staged` | `vp staged` | `.lintstagedrc*`、`lint-staged.config.*`、`lint-staged` 依赖、`package.json#lint-staged` |
| `husky` / `simple-git-hooks` / `lefthook` / `yorkie` / `pre-commit` | `vp hooks` | `.husky/`、`lefthook.yml`、`package.json#simple-git-hooks`、`package.json#lint-staged`、对应依赖、`prepare`/`postinstall` 里的旧 hook 安装命令 |
| `tsdown` / `tsup` / `unbuild` / 手写 rollup 库构建 | `vp pack` | 对应配置文件与依赖 |
| `vitest` | `vp test` | 独立的 `vitest.config.*`(迁移进 `vite.config.ts`) |
| `vite` | `vp dev` / `vp build` / `vp preview` | 独立的 `vite.config.*`(按模板重写) |
| `npm-check-updates` 脚本 | `soy ncu` | 自建升级脚本 |
| `standard-version` / 自写 release 脚本 | `soy release` | 对应脚本与依赖 |
| `.nvmrc` / Volta 的 `volta.node` | `.node-version` | 旧文件 |

**模板里没有对应能力的工具不要删**。例如 `commitlint`、`cz-git`、`sui`、`typedoc`、`size-limit` —— 模板对此沉默,说明它们不属于"被替代",保留原状并写进最终报告。

## 迁移前勘察

先落一个专用分支,再动手:

```bash
git switch -c chore/standardize
git status --porcelain      # 必须为空;有未提交改动时停下,让用户先 commit 或 stash
```

按顺序采集现状,后面每一步的删除清单都从这里来:

1. 包管理器:`packageManager` 字段、是否存在 `pnpm-lock.yaml`。**不是 pnpm 项目时停下问用户**,不要自行换包管理器。
2. `package.json` 全文:scripts、dependencies、devDependencies、以及 `lint-staged` / `simple-git-hooks` / `husky` / `prettier` / `pnpm` 等顶层配置键。
3. 根目录所有 `.` 开头的配置文件:`ls -a`。
4. Git hooks 现状:`ls -a .husky .vite-hooks 2>/dev/null; git config core.hooksPath`。
5. 构建/测试入口:是否存在 `vite.config.*`、`vitest.config.*`、`tsconfig.json`。
6. 框架特征文件:是否存在 `**/*.vue`、`src/App.vue`。
7. **monorepo 额外**:`pnpm-workspace.yaml` 的 `packages:` glob,展开出的每个子包的 `package.json`(name、scripts、deps、peerDependencies)、`tsconfig.json`、`vite.config.*`。子包是否 `extends` 根 tsconfig、`exports` 是否区分 `src`/`publishConfig.exports` 到 `dist`。

## 迁移步骤

1. **判定模板类型**,按上面「适用范围」的证据规则选定 `templates/ts` 或 `templates/vue-ts`。判不出来就停下问用户,不要两头都套。monorepo 先确定主体子包,再按下面的「pnpm monorepo」处理子包。

2. **逐文件对照模板落盘**。对模板里的每个文件,判断它是"覆盖"还是"合并":
   - **直接覆盖**:`.editorconfig`、`.gitattributes`、`.vite-hooks/pre-commit`、`vite.config.ts`、`eslint.config.mjs`(vue-ts)。
   - **以模板为基线但必须保留项目扩展**:
     - `tsconfig.json` —— `compilerOptions` 按模板对齐(strict 系列、`moduleResolution`、`isolatedModules`),但项目自己的 `paths` 别名、`types`(例如 `naive-ui/volar`、`unplugin-icons/types/vue`、`vite/client`)、`jsxImportSource`、`include`/`exclude` 一律保留。
     - `pnpm-workspace.yaml` —— **只在单包项目里可覆盖**。monorepo 必须保留原有 `packages:`、`overrides`、`peerDependencyRules` 等键,只对齐 `catalog` 与 `allowBuilds`。
     - `.vscode/settings.json` —— 模板键按模板取值,项目特有键(i18n-ally、`unocss.root` 等)保留。
   - **合并**:`.gitignore`(保留项目自定义条目,补上模板缺的)、`.vscode/launch.json`(保留项目已有的调试配置,补上模板的 TS Debugger)。
   - **只新增不覆盖**:`.github/workflows/pr-agent.yml`;`AGENTS.md`(若项目已有同名文件,把模板内容并进对应小节)。

3. **合并 `package.json`**。这是唯一需要精细处理的文件:
   - **模板决定**:`scripts`(全部用模板版本)、`type`、`packageManager`、`devDependencies` 中与工具链有关的部分(`@soybeanjs/cli`、`@soybeanjs/oxc-config`、`vite-plus`、`tsx`、`typescript`、`@types/node`)。
   - **vue-ts 额外**:`@soybeanjs/eslint-config-vue`、`eslint`、`@vitejs/plugin-vue`、`@vitejs/plugin-vue-jsx`、`vue-tsc`。
   - **保留原样**:`name`、`version`、`description`、`license`、`author`、`repository`、`homepage`、`bugs`、`bin`、`files`、`exports`、`main`/`module`/`types`、`publishConfig`,以及所有 `dependencies`(运行依赖)。不要用模板里的 `my-ts-project` / `my-vue-project` 覆盖项目自己的 `name`。
   - **删除**:对照表里列出的、被 Vite+ 替代的工具依赖与配置键。
   - 模板的 `scripts` 键顺序是字母序,合并后保持这个顺序。

4. **重写资产引用**。原 `vite.config.*` 里的 `resolve.alias`、`server`、`build`、`css`、`define` 等业务配置,迁到新 `vite.config.ts` 里保留;模板已提供 `resolve.tsconfigPaths: true`,与 `tsconfig.json` 的 `paths` 重复的 alias 直接删掉。原配置里的 `plugins` 数组整体搬到模板的 `plugins` 字段(vue-ts 模板已含 `vue()` 与 `vueJsx()`)。

5. **接上 Git hooks**:
   - 落盘 `.vite-hooks/pre-commit`(内容 `vp staged`)。
   - 在 `package.json#scripts` 加 `"prepare": "vp config --no-agent"`。
   - 删除旧 hook 工具的文件、依赖、配置键与安装命令。
   - 模板的 `vite.config.ts` 已含 `staged: { '*': 'vp check --fix' }`,不要另建 staged 配置。
   - **验证时机很重要**:`vp config --no-agent` 只在 `pnpm install` 走完依赖安装后才执行,所以第 6 步装完依赖后才看 `git config core.hooksPath`。此时仍为空时手动补一次 `pnpm exec vp hooks enable`。

6. **重新安装**:

   ```bash
   pnpm install
   ```

   非零退出时按下面「安装期报错」处理,不要跳过往后走。

7. **跑验证**(模板里有的脚本才跑,不要臆造命令名):

   ```bash
   pnpm fmt
   pnpm lint
   pnpm typecheck
   pnpm build
   ```

8. **报告并提交**。提交信息用英文 Conventional Commits(`chore(<scope>):` 前缀),把"改了哪些工具链""删了哪些旧工具""哪些保留待用户决策"写进正文。

## pnpm monorepo

模板是单包结构,monorepo 要把它拆成**根工作区**与**子包**两层。原则:**工作区级的工具链统一到根,子包的构建/类型检查自己持有**。

### 根目录(工作区)

- `pnpm-workspace.yaml` —— 保留原有 `packages:`、`overrides`、`peerDependencyRules`、`shamefullyHoist` 等键,只把 `catalog` 对齐模板(`vite`、`vite-plus`),必要时追加 `allowBuilds`。**不要**用模板的三行内容整体覆盖。
- 根 `package.json` —— 只放工作区级工具链:`@soybeanjs/cli`、`@soybeanjs/oxc-config`、`@types/node`、`tsx`、`typescript`、`vite-plus`(vue-ts 另加 `@soybeanjs/eslint-config-vue`、`eslint`);保留项目已有的 `typedoc`/`commitlint`/`cz-git`/`sui` 之类工作区级依赖。scripts 保留 `pnpm --filter` 聚合形式,只改被替代的部分(如 `lint` 里的 `prettier`/`eslint` 调用)。整体是 `private: true`,不加 `bin`/`exports`。
- `tsconfig.json`(根)—— 只作**共享基线**:`target`/`lib`/`module`/`moduleResolution`/strict 系列/`isolatedModules`/`skipLibCheck`,以及 vue-ts 的 `jsx`/`jsxImportSource`。**不放** `paths`、`include`——那些属于子包。
- `vite.config.ts`(根)—— 只保留 `staged`/`lint`/`fmt`。**不要**放 `pack`/`plugins`/`resolve`/`test`——除非项目有跨包统一的 test 配置需求。
- `.editorconfig`、`.gitattributes`、`.gitignore`、`.vite-hooks/pre-commit`、`.vscode/*`、`eslint.config.mjs`、`.github/workflows/pr-agent.yml`、`AGENTS.md` —— 同样按「逐文件对照模板落盘」处理,位置在根(只放一份,子包不重复)。
- 根不加 `build` 到 `vp pack`。原来的聚合构建脚本(`pnpm build:libs && pnpm build:ui && ...`)保留原样。

### 子包

对每个子包**逐个**执行模板对齐,而不是只改根:

- `tsconfig.json` —— 以 `extends: "../../tsconfig.json"` 继承根基线(项目已有的话保留),子包自己提供 `types`、`paths`、`include`。不要往子包写完整的 `compilerOptions` 副本。
- `vite.config.ts` —— 子包各持有一份,这是与单包模板最大的差异。`resolve.tsconfigPaths: true` 与 `pack` 配置入口属于子包;`staged`/`lint`/`fmt` 只在根放一份,子包不重复。
- `package.json` —— 子包的 `build`/`test`/`typecheck` 按模板能力改写(`tsc --noEmit` 或 `vue-tsc`、`vp pack`、`vp test run`),但 **`exports`/`main`/`module`/`types`/`publishConfig`/`bin`/`files` 必须原样保留**。这套"开发期指向 `src`、发布期指向 `dist`"的 `publishConfig.exports` 是 monorepo 库的分发约定,模板里没有,不要改动。
- `package.json` 的 `devDependencies` —— 子包只依赖自己直接用的工具(如 `vue-tsc`),工作区级工具链(oxc-config、cli、vite-plus)留在根。
- 子包的 `dependencies`/`peerDependencies`(如 vue、vue-router、nuxt)全部保留。

### 属于项目自处理的配置(不要碰)

模板对以下东西沉默,迁移时保留原状,并在报告里列为"未迁移,待确认":

- 聚合/发布脚本:`build:libs`、`publish-pkg`、`release-execute`、`sync-template-versions`、`stub` 等 `pnpm --filter`/`pnpm -r` 编排。
- 仓库自有的 `sui` 脚本(`sui check deps`、`sui gen`、`sui translate`、`sui size`)、`packages/scripts` 目录、`tsx` 直跑的入口。
- 子包的风味构建插件:已改过的 `pack.plugins`(如 `unplugin-vue/rolldown`)、`pack.deps.neverBundle`、`pack.unbundle`、`pack.define`、`pack.dts.vue`、CSS 构建(`build:css`)、`test.environment`/`setupFiles`/`test:browser` 配置。
- 文档站包(如 `apps/docs`、VitePress)、e2e 专项配置。
- 工作区级的其它工具配置(typedoc、commitlint、`.npmrc`)。

判定边界:模板有对应能力的才改;模板没提的构建细节与业务编排一律保留。不确定时保留旧行为并在报告里说明。

## 安装期报错

### `ERR_PNPM_IGNORED_BUILDS`

```
Error: ERR_PNPM_IGNORED_BUILDS
  × installing dependencies
  ╰─▶ Ignored build scripts: esbuild@0.28.2
```

pnpm 11+ 默认不执行依赖的构建脚本,而 `tsx` 会把 `esbuild` 作为直接依赖引入,于是**每次冷装都会命中**。在 `pnpm-workspace.yaml` 里逐包表态:

```yaml
allowBuilds:
  esbuild: false
```

取值规则:`false` 表示明确不信任该构建脚本。实测 `esbuild: false` 下 `vp fmt` / `vp lint` / `vp typecheck` / `vp build` 全部正常(esbuild 的平台二进制由 optionalDependencies 分发,不需要 postinstall)。**只有确认某包必须跑 postinstall 才能工作时才写 `true`**(例如需要 node-gyp 编译的原生模块)。

三条纪律:

- 必须写**报错里点名的那个包名**。写错包名(例如把 `esbuild` 写成项目自有的包)不会消错,报错照旧。
- 保留项目 `allowBuilds` 里已有条目的原值,只增不改。
- 不要用 `dangerouslyAllowAllBuilds: true`,也不要用 `pnpm approve-builds --all` / `vp pm approve-builds --all`,那等于放弃信任决策。

### 其他非零退出

版本冲突、peer 冲突、完整性校验、网络/registry 失败 —— 读完整错误信息再决定。根因与处置写进最终报告,不要静默降级版本。

## 不要覆盖的东西

- `src/` 下的业务代码。本 skill 只改工程配置,不改实现。
- 所有 `dependencies`(运行依赖)。只删"被 Vite+ 替代的工具"这一类 devDependency。
- `README*`、`LICENSE`、`CHANGELOG.md`。
- 模板沉默的第三方工具(commitlint、typedoc、size-limit 等):保留,并在报告里列为"未迁移,待确认"。
- CI workflow 里与业务相关的 job。只有显式调用 `prettier` / `eslint` / `lint-staged` / `vitest` 的步骤需要改成 `vp fmt` / `vp lint` / `vp staged` / `vp test`。

## 可选:官方 `vp migrate`

`pnpm dlx --package=vite-plus@latest vp migrate --no-interactive` 能自动改写 imports、把 `vite` 换成 `catalog:`、把 Prettier 配置翻译成 Oxfmt。**但它有两个已知缺口,所以不能替代本 skill**:

- 检测到 `husky`、`simple-git-hooks`、`lefthook`、`yorkie` 时会**主动跳过** hook 设置并只打一条 warning —— hook 部分无论如何都得手工按第 5 步做。
- 它按自己的风格重写 `vite.config.ts`(例如包一层 `lazyPlugins`),产物与模板不一致,跑完还要再对齐一次。

只在项目里 `vite` / `vitest` 的 import 需要大范围改写时才考虑用它当加速器,用完必须逐文件对照模板复核。

## 验证

迁移完成的判定标准,四条都要过:

1. `pnpm install` 退出码为 0,且不再出现 `ERR_PNPM_IGNORED_BUILDS`。
2. `pnpm fmt`、`pnpm lint`、`pnpm typecheck`、`pnpm build`(库项目是 `vp pack`)全部通过。vue-ts 项目额外确认 `pnpm exec eslint .` 无报错。
3. 对模板里的每个文件逐个 diff 确认已对齐;对照表里列出的旧配置文件已从磁盘删除,对应依赖已从 `package.json` 删除,对应配置键已消失。
   - monorepo 额外:根与**每个**子包都单独 diff;`pnpm -r typecheck`(或根 `pnpm typecheck`)全过;子包 `exports`/`publishConfig` 与迁移前一致。
4. `git config core.hooksPath` 输出 `.vite-hooks/_`,且提交时能看到 `vp staged` 的输出(空提交即可触发,会打印 `lint-staged could not find any staged files.`)。验证完用 `git reset --soft HEAD~1` 撤回这个空提交 —— 不要用 `--hard`,迁移期工作区可能还有未提交的改动。

## 反例

- 不改 `package.json`,只把配置文件复制过去 —— 旧工具还在 devDependencies 里,新脚本和旧依赖打架。
- 删了 `.prettierrc` 却把 `prettier` 留在 devDependencies,或反过来只删依赖不删文件。
- 保留 `lint-staged` 配置块,同时又写 `staged: { '*': 'vp check --fix' }` —— 两套 staged 策略并存,提交时行为不确定。
- 保留 `simple-git-hooks` 的 `prepare` 脚本,又加 `vp config` —— 每次安装跑两个 hook 安装器,`.git/hooks` 被反复覆盖。
- 只删 `.husky/` 目录,不删 `.git/hooks` 里的残留,也不删 `core.hooksPath` 指向,提交时旧 hook 仍在跑。
- 在 `scripts` 里写 `vite build` / `vite dev` —— `vite-plus` 只提供 `vp` 和 `vpr` 两个 bin,没有 `vite`,会直接 `sh: vite: command not found`。
- 用 `templates/ts` 或 `templates/vue-ts` 里的示例 `name`(`my-ts-project` / `my-vue-project`)覆盖项目真实包名。
- 把 `dependencies` 里的运行依赖当"旧工具"删掉。
- 遇到 `ERR_PNPM_IGNORED_BUILDS` 就用 `--all` 放行,或把不存在的包名写进 `allowBuilds` 后继续往下走。
- 装了依赖没跑验证就提交,把红着的 lint/typecheck 状态留给用户。
- 把 React / Nuxt 项目硬套 `vue-ts` 模板。
- 迁移和业务代码修改混在同一个提交里,无法单独 revert。
- monorepo 里把模板的 `pnpm-workspace.yaml` 三行内容整体覆盖到根 —— 原有的 `packages:`、`overrides` 被删,工作区直接失效。
- monorepo 只改根 `package.json` 与根配置,子包一个没动 —— 子包仍跑旧脚本(`prettier`/`lint-staged`),根上统一了也不算迁移完成。
- 把子包的 `publishConfig.exports`(`dist`)改成 `src`,或直接用模板的 `exports` 覆盖 —— 发布产物失效。
- 在根 `vite.config.ts` 写 `pack`/`plugins`,又保留每个子包自己的 `vite.config.ts` —— 两份配置冲突,子包构建行为不确定。
