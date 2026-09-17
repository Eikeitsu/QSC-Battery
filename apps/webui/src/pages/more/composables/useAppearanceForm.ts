import { computed, ref, watch } from "vue";
import { MD3_CUSTOM_ID, MD3_SEED_PRESETS, PACK_HINT, THEME_DEFAULTS } from "@/shared";
import { useTheme } from "@/stores";

export function useAppearanceForm() {
  const theme = useTheme();
  const fontDraft = ref(Number(theme.fontScale));
  const md3ForceCustom = ref(false);
  const seedInput = ref<HTMLInputElement | null>(null);
  const seedHexDraft = ref("");

  watch(
    () => theme.fontScale,
    (v) => {
      fontDraft.value = Number(v);
    },
  );

  watch(
    () => theme.md3Seed,
    (v) => {
      seedHexDraft.value = String(v || THEME_DEFAULTS.md3Seed);
    },
    { immediate: true },
  );

  const packLabel = computed(() => PACK_HINT[theme.themePack]);

  const md3ChipValue = computed(() => {
    if (md3ForceCustom.value) return MD3_CUSTOM_ID;
    const seed = String(theme.md3Seed || "").toUpperCase();
    const hit = MD3_SEED_PRESETS.find(
      (p) => p.id !== MD3_CUSTOM_ID && p.id.toUpperCase() === seed,
    );
    return hit ? hit.id : MD3_CUSTOM_ID;
  });

  const md3CustomSeed = computed(() => md3ChipValue.value === MD3_CUSTOM_ID);

  function onMd3Chip(id: string | number) {
    const raw = String(id);
    if (raw === MD3_CUSTOM_ID) {
      md3ForceCustom.value = true;
      seedHexDraft.value = String(theme.md3Seed || THEME_DEFAULTS.md3Seed);
      return;
    }
    md3ForceCustom.value = false;
    theme.setMd3Seed(raw);
  }

  function openSeedPicker() {
    seedInput.value?.click();
  }

  function onSeedInput(e: Event) {
    const v = (e.target as HTMLInputElement).value;
    seedHexDraft.value = v;
    theme.setMd3Seed(v, false);
  }

  function onSeedHexCommit() {
    const raw = String(seedHexDraft.value || "").trim();
    if (!raw) return;
    theme.setMd3Seed(raw, true);
    seedHexDraft.value = String(theme.md3Seed);
  }

  function onFontDrag(v: number) {
    fontDraft.value = Number(v);
  }

  function onFontCommit(v: number) {
    theme.setFontScale(v, true);
    fontDraft.value = Number(theme.fontScale);
  }

  return {
    theme,
    packLabel,
    fontDraft,
    md3ChipValue,
    md3CustomSeed,
    seedInput,
    seedHexDraft,
    onMd3Chip,
    openSeedPicker,
    onSeedInput,
    onSeedHexCommit,
    onFontDrag,
    onFontCommit,
  };
}
