import { defineAsyncComponent, type Component, type AsyncComponentLoader } from "vue";
import BlockSkeleton from "@/shared/ui/BlockSkeleton.vue";

/**
 * 异步组件不参与父级 Suspense，避免一个卡片的 chunk 阻塞整页。
 * 页面先渲染骨架，组件自身显示轻量占位。
 */
export function lazyComponent(loader: AsyncComponentLoader<Component>) {
  return defineAsyncComponent({
    loader,
    loadingComponent: BlockSkeleton,
    delay: 150,
    timeout: 15_000,
    suspensible: false,
  });
}
