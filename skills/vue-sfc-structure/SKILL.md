---
name: vue-sfc-structure
description: Vue SFC 结构规范。处理 **/*.vue 文件时必须遵守的 script setup 组织顺序与职责分层规则:定义顺序、shallowRef 选择、template 绑定函数、attrs 继承等最佳实践。
---

# Vue SFC 结构规范

这份规范用于本项目所有 `.vue` 文件，重点约束 `script setup` 的组织顺序与职责分层。

## 适用范围

- 文件匹配：`**/*.vue`。
- 适用对象：使用 `<script setup>` 的 Vue 单文件组件。
- 不适用对象：无 `<script setup>` 的纯模板组件或非 SFC 写法。

## 目标

- 让组件脚本结构稳定、可预测、便于扫描。
- 把类型定义、响应式状态、context provider、watch、生命周期分层放置，减少来回跳读。

## script setup 顺序

推荐顺序如下：

1. import statements
2. `defineOptions`
3. props 类型定义或 `import type`
4. `defineProps`
5. emits 类型定义或 `import type`
6. `defineEmits`
7. slots 类型定义或 `import type`
8. `defineSlots`
9. hooks / composables 初始化
10. 组件业务逻辑，按语义分块
11. 必要的 `init` 函数
12. context provider
13. `watch` / `watchEffect`
14. 生命周期 hooks
15. `defineExpose`

## 详细说明

### defineOptions

- `defineOptions` 尽量靠前，通常紧跟 imports 后。
- 组件 `name` 遵循项目既有命名约定。

### props / emits / slots 类型定义

- 项目有 `types.ts` 惯例时，优先从同级 `types.ts` 导入类型。
- 如果类型很简单，也可以在当前文件内直接声明小型 interface 或 tuple-style 类型。

### defineProps / defineEmits / defineSlots

- 不使用时不传变量，直接 `defineXxx<Type>()`。
- 脚本里需要访问时，用 `const xxx = defineXxx<Type>()`。
- 即使脚本里保留了 `props` 对象，模板里也直接使用 prop 名，不写 `props.xxx`。

### hooks / composables 初始化

- `useRoute`、`useRouter` 这类初始化逻辑放在这里。
- 这一段只做"拿能力"和"拿基础上下文"，不要混入大量业务计算。

### 组件业务逻辑

- 按业务语义分块，而不是按 API 类型混排。
- 相关的 `ref`、`computed`、函数尽量靠近放置。
- 对对象、数组、实例句柄等不需要深层响应式的数据，优先使用 `shallowRef` 而不是 `ref`。

### 响应式引用选择

- 需要追踪基础值或确实依赖深层属性响应式更新时，使用 `ref`。
- 如果只关心 `.value` 整体替换，而不需要内部深层属性自动追踪，优先使用 `shallowRef`。
- 尤其是对象、数组、第三方实例、DOM 句柄、上下文状态容器这类值，默认先考虑 `shallowRef`。
- 只有需要依赖对象内部字段变化触发更新时，才更适合继续使用 `ref`。

### init 函数

- 只有在确实存在初始化流程时才定义 `init`。
- 初始化逻辑集中到一个函数里，避免散落到多个生命周期钩子中。

### context provider

- `provideXxx` 这类 provider 放在业务逻辑之后、watch 与生命周期之前。
- 先把要提供的数据准备好，再统一注入，避免 provider 之前和之后来回穿插定义状态。

### watch / watchEffect

- `watch`、`watchEffect` 放在 provider 之后。
- 没必要时不要引入 watcher；优先考虑 `computed` 或直接事件流。

### 生命周期 hooks

- 生命周期钩子放在 script 末段。
- 若存在 `init()`，通常在这里或等价创建阶段调用，保持初始化入口集中。

### defineExpose

- `defineExpose` 放在脚本最后。
- 只有组件确实需要暴露实例 API 时才使用。

### template 绑定函数

- template 中绑定到事件、插槽参数回调或属性的函数实现，必须写在 `script setup` 里，或从外部显式导入后再在 template 中引用。
- 不要在 template 里直接写内联箭头函数、匿名函数或承载业务逻辑的函数实现；template 只负责绑定已经在脚本中定义好的函数。
- 允许在 template 中给脚本内已定义的函数传参，例如 `@click="handleSelect(item.id)"`；不允许直接写 `@click="() => handleSelect(item.id)"` 这类内联实现。

### attrs 继承

- 若 template 只有一个非 slot 根标签，并且 attrs 本来就应该整体落到这个根标签上，则不要设置 `inheritAttrs: false`，也不要为了透传根 attrs 额外写 `useAttrs()` + `v-bind="attrs"`。
- 优先使用 Vue 默认的 attrs 继承，让调用方传入的普通 attrs 自动绑定到根标签，减少样板代码和无意义的转发层。
- 只有在以下场景才使用 `inheritAttrs: false` 或手动消费 `useAttrs()`：需要把 attrs 拆分到多个节点；需要过滤或改写 attrs；需要把 attrs 转交给非根节点；需要在脚本逻辑中显式读取 attrs；或者组件本身不是单个可直接承接 attrs 的根标签结构。

### 其他

- 若组件非常简单，不必为了凑顺序硬塞空分区；顺序是为了增强可读性，不是制造样板代码。

## 检查问题

- `defineOptions` 是否足够靠前？
- props / emits / slots 类型与 `defineProps` / `defineEmits` / `defineSlots` 是否成对且顺序稳定？
- hooks 初始化、业务逻辑、provider、watch、生命周期是否分层清楚？
- 如果 template 是单个可承接 attrs 的非 slot 根标签，是否避免了不必要的 `inheritAttrs: false` 和手动 `useAttrs()` 透传？
- template 中绑定的函数是否都已经在 `script setup` 中定义或导入，而不是写成内联实现？
- 不需要深层响应式的状态是否优先使用了 `shallowRef`？
- 是否为了形式保留了不必要的 `init`、watch、`defineExpose`？

## 完整示例

以下示例展示上述顺序与最佳实践在一个典型组件中的落地：

```vue
<script setup lang="ts">
import { computed, onMounted, ref, shallowRef, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import type { OptionItem } from './types';
import { provideFilterContext } from './context';

// 1. defineOptions
defineOptions({ name: 'FilterPanel' });

// 2-3. props 类型定义 + defineProps
interface Props {
  modelValue: string;
  options: OptionItem[];
}
const props = defineProps<Props>();

// 4-5. emits 类型定义 + defineEmits
interface Emits {
  (e: 'update:modelValue', value: string): void;
  (e: 'change', value: OptionItem): void;
}
const emit = defineEmits<Emits>();

// 6. hooks / composables 初始化
const route = useRoute();
const router = useRouter();

// 7. 组件业务逻辑(按语义分块,shallowRef 用于不需要深层响应式的数据)
const listRef = shallowRef<OptionItem[]>(props.options);
const keyword = ref('');

const filtered = computed(() => {
  const kw = keyword.value.trim().toLowerCase();
  return kw ? listRef.value.filter(item => item.label.toLowerCase().includes(kw)) : listRef.value;
});

// 8. template 绑定的函数:在脚本中定义,模板只负责引用
function handleSelect(item: OptionItem) {
  emit('update:modelValue', item.value);
  emit('change', item);
}

// 9. init 函数(仅在确实存在初始化流程时)
function init() {
  const initial = route.query.keyword;
  if (typeof initial === 'string') {
    keyword.value = initial;
  }
}

// 10. context provider
provideFilterContext({ keyword, filtered });

// 11. watch / watchEffect(仅在必要时引入)
watch(keyword, value => {
  router.replace({ query: { ...route.query, keyword: value || undefined } });
});

// 12. 生命周期 hooks
onMounted(() => {
  init();
});

// 13. defineExpose(仅在需要暴露实例 API 时)
defineExpose({ reset: () => (keyword.value = '') });
</script>

<template>
  <div class="filter-panel">
    <input v-model="keyword" placeholder="搜索" />
    <ul>
      <li
        v-for="item in filtered"
        :key="item.value"
        @click="handleSelect(item)"
      >
        {{ item.label }}
      </li>
    </ul>
  </div>
</template>
```

要点回顾：

- `defineOptions` 紧跟 imports，后续按 props → emits → hooks → 业务逻辑 → provider → watch → 生命周期的稳定顺序排布。
- 不需要深层响应式的 `listRef` 使用 `shallowRef`；需要追踪输入值的 `keyword` 使用 `ref`。
- template 中 `@click="handleSelect(item)"` 引用的是脚本中已定义的函数，未使用内联箭头函数。
- 单根标签结构且 attrs 应整体落到根标签，未设置 `inheritAttrs: false`。
