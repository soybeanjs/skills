# SoybeanJS Skills

SoybeanJS 团队的 Agent Skills 集合，为 AI Agent 提供统一的前端编码规范。

## 特性

- **聚焦前端**：涵盖 TypeScript 逻辑代码、Vue SFC 组件结构、pnpm 依赖升级与工程模板迁移四大核心场景。
- **开箱即用**：通过 `skills` CLI 或 Claude Code Marketplace 一键安装，Agent 自动按文件类型或任务类型加载对应规范。
- **职责分层**：编码规范与任务流程分离，可独立使用也可配套使用。
- **实战导向**：每条规则配有正反示例与检查清单，降低 Agent 与人类的理解成本。

## 包含的 Skills

| Skill | 文件匹配 | 说明 |
| --- | --- | --- |
| [`typescript-functional-style`](skills/typescript-functional-style/SKILL.md) | `**/*.{ts,tsx,js,jsx}` | TypeScript 函数式风格规范：优先纯函数与组合，限制可变性，类型必须精确，保持声明式数据变换。 |
| [`vue-sfc-structure`](skills/vue-sfc-structure/SKILL.md) | `**/*.vue` | Vue SFC 结构规范：`script setup` 组织顺序与职责分层，涵盖 `shallowRef` 选择、template 绑定函数、attrs 继承等最佳实践。 |
| [`pnpm-deps-upgrade`](skills/pnpm-deps-upgrade/SKILL.md) | pnpm 项目 | pnpm 依赖升级流程：校验工作区干净且同步 → `pnx npm-check-updates -u [-w]` → 重装依赖并修复 `allowBuilds` 构建拦截 → typecheck/test → 提交推送。 |
| [`soybean-standard-projects`](skills/soybean-standard-projects/SKILL.md) | TS / Vue+TS 项目（含 pnpm monorepo） | 工程规范迁移：按 `templates/ts` 或 `templates/vue-ts` 模板对齐项目，用 vite-plus 统一取代 vite、vitest、eslint、prettier、lint-staged、husky 等分散工具链。 |

前两个规范配套使用：前者约束 TS/JS 逻辑代码的写法，后者约束 Vue 组件的脚本组织与分层。`pnpm-deps-upgrade` 与 `soybean-standard-projects` 面向任务流程：前者在用户要求升级项目依赖时触发，后者在用户要求项目规范化改造时触发。

## 安装

### 方式一：skills CLI

```bash
npx skills add soybeanjs/skills
```

`skills` CLI 会自动将包内所有 skill 安装到对应 Agent 的 skills 目录。

### 方式二：Claude Code Marketplace

在 Claude Code 中执行以下命令：

```bash
/plugin marketplace add soybeanjs-skills
/plugin install soybeanjs-skills@soybeanjs-skills
```

## 使用说明

安装完成后无需手动操作。Agent 在处理匹配文件时会自动加载对应规范：

- 处理 `.ts`、`.tsx`、`.js`、`.jsx` 文件时，自动应用 `typescript-functional-style` 规范。
- 处理 `.vue` 文件时，自动应用 `vue-sfc-structure` 规范。
- 要求升级项目依赖时，自动应用 `pnpm-deps-upgrade` 流程。
- 要求把项目迁移到标准工程模板时，自动应用 `soybean-standard-projects` 流程（仅限 TS 与 Vue+TS 两类项目）。

每个 SKILL.md 内均包含完整规则说明、正反示例与检查清单，可直接查阅。

## License

[MIT](LICENSE)
