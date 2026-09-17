<script setup lang="ts">
import { computed } from "vue";
import { parsePercent } from "@/shared/lib/batteryDisplay";

const props = withDefaults(
  defineProps<{
    level?: string;
    charging?: boolean;
    size?: number;
    variant?: "hero" | "md3" | "miuix";
  }>(),
  {
    level: "--",
    charging: false,
    size: 36,
    variant: "md3",
  },
);

const pct = computed(() => parsePercent(props.level) ?? 0);
const known = computed(() => parsePercent(props.level) !== null);

const fillColor = computed(() => {
  if (!known.value) return "var(--qsc-text-3)";
  if (pct.value <= 15) return "var(--van-danger-color, #ef4444)";
  if (pct.value <= 30) return "var(--van-warning-color, #f59e0b)";
  return "var(--qsc-primary)";
});

const frameRx = computed(() => (props.variant === "miuix" ? 3.5 : 4));
</script>

<template>
  <span
    class="batt-glyph"
    :class="[`batt-glyph--${variant}`, { 'is-charging': charging, 'is-unknown': !known }]"
    :style="{ width: `${size}px`, height: `${size * 0.55}px`, '--batt-fill': fillColor }"
    role="img"
    :aria-label="known ? `电量 ${pct}%` : '电量未知'"
  >
    <svg class="batt-glyph__svg" viewBox="0 0 48 26" aria-hidden="true">
      <rect
        class="batt-glyph__frame"
        x="1.5"
        y="3.5"
        width="40"
        height="19"
        :rx="frameRx"
        fill="none"
        stroke-width="2"
      />
      <path
        class="batt-glyph__cap"
        d="M43 9.5h2.5a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H43"
        fill="currentColor"
        opacity="0.45"
      />
      <defs>
        <clipPath :id="`batt-clip-${variant}-${size}`">
          <rect x="4" y="6" width="35" height="14" :rx="Math.max(1.5, frameRx - 1.5)" />
        </clipPath>
      </defs>
      <g :clip-path="`url(#batt-clip-${variant}-${size})`">
        <rect
          class="batt-glyph__level"
          x="4"
          y="6"
          :width="known ? (35 * pct) / 100 : 0"
          height="14"
          :rx="1.5"
        />
        <rect
          v-if="charging && known"
          class="batt-glyph__shine"
          x="4"
          y="6"
          width="12"
          height="14"
        />
      </g>
      <path
        v-if="charging"
        class="batt-glyph__bolt"
        d="M24.8 7.2 20.2 13.8h3.2l-1.4 5.2 5.4-7.8h-3.2z"
        fill="currentColor"
      />
    </svg>
  </span>
</template>

<style scoped lang="scss">
.batt-glyph {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: var(--qsc-text-2);
  flex-shrink: 0;
}

.batt-glyph__svg {
  width: 100%;
  height: 100%;
  display: block;
  overflow: visible;
}

.batt-glyph__frame {
  stroke: currentcolor;
}

.batt-glyph__level {
  fill: var(--batt-fill);
  transition: width 0.45s ease;
}

.batt-glyph__shine {
  fill: color-mix(in srgb, #fff 55%, transparent);
  animation: batt-shine 1.6s ease-in-out infinite;
}

.batt-glyph__bolt {
  opacity: 0.92;
  filter: drop-shadow(0 0 1px color-mix(in srgb, var(--batt-fill) 40%, transparent));
}

.batt-glyph--hero {
  color: var(--qsc-text);
}

.batt-glyph--miuix {
  color: var(--qsc-text-2);
}

.batt-glyph.is-charging .batt-glyph__frame {
  animation: batt-pulse 1.8s ease-in-out infinite;
}

@keyframes batt-shine {
  0% {
    transform: translateX(-14px);
    opacity: 0;
  }

  35% {
    opacity: 0.7;
  }

  100% {
    transform: translateX(38px);
    opacity: 0;
  }
}

@keyframes batt-pulse {
  0%,
  100% {
    opacity: 1;
  }

  50% {
    opacity: 0.72;
  }
}

@media (prefers-reduced-motion: reduce) {
  .batt-glyph__shine,
  .batt-glyph.is-charging .batt-glyph__frame {
    animation: none;
  }
}
</style>
