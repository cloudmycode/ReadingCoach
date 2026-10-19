<template>
  <AppLayout>
    <section class="panel">
      <div class="panel__header">
        <div>
          <h2>生词本</h2>
          <p class="muted">共 {{ items.length }} 个单词，已学会的单词可移出复习任务，保留来源句子。</p>
        </div>
        <div class="actions">
          <button class="button button--secondary" type="button" @click="loadEntries">
            刷新
          </button>
          <RouterLink class="button button--ghost" to="/review-tasks">
            查看复习任务
          </RouterLink>
        </div>
      </div>

      <p v-if="loading" class="muted">加载中...</p>
      <p v-else-if="errorMessage" class="error-text">{{ errorMessage }}</p>

      <div v-else-if="items.length === 0" class="empty-state">
        暂无生词，先去 App 中点查几个单词吧。
      </div>

      <div v-else class="record-list">
        <article v-for="item in items" :key="item.entry_id" class="record-card">
          <div class="record-card__main">
            <div class="record-card__title-row">
              <h3>{{ item.word }}</h3>
              <span v-if="item.mastery_status" class="record-badge">
                {{ item.mastery_status === "mastered" ? "已学会" : item.mastery_status === "paused" ? "已暂停" : "学习中" }}
              </span>
            </div>
            <p class="record-card__meta">
              {{ item.part_of_speech || "词性未标注" }} ·
              {{ item.article_id ? "已关联文章" : "未关联文章" }}
            </p>
            <p class="record-card__desc">{{ item.meaning || item.tip || "暂无释义" }}</p>
            <p class="record-card__quote">{{ item.sentence_original }}</p>
            <p class="record-card__translation">{{ item.sentence_translation }}</p>
            <p class="record-card__submeta">
              收录时间：{{ formatDateTime(item.looked_up_at) }}
              <span v-if="item.next_review_at"> · 下次复习：{{ item.next_review_at }}</span>
            </p>
          </div>
          <div class="record-card__actions">
            <RouterLink class="button button--ghost" :to="`/articles/${item.article_id}`">
              查看文章
            </RouterLink>
            <button
              v-if="item.mastery_status === 'learning'"
              class="button button--secondary"
              type="button"
              :disabled="savingEntryIds.has(item.entry_id)"
              @click="handleMastered(item.entry_id)"
            >
              已学会，移出任务
            </button>
            <button
              class="button button--danger"
              type="button"
              @click="handleDelete(item.entry_id, item.word)"
            >
              删除单词
            </button>
          </div>
        </article>
      </div>
    </section>
  </AppLayout>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue";
import { RouterLink } from "vue-router";
import AppLayout from "../components/AppLayout.vue";
import { ApiError, formatDateTime } from "../api/client";
import { deleteWordBookEntry, listWordBook } from "../api/word-book";
import { markWordMastered } from "../api/review";
import type { WordBookItem } from "../types/api";

const items = ref<WordBookItem[]>([]);
const loading = ref(false);
const errorMessage = ref("");

async function loadEntries() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const data = await listWordBook();
    items.value = data.items;
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

const savingEntryIds = ref<Set<number>>(new Set());

async function handleMastered(entryId: number) {
  if (savingEntryIds.value.has(entryId)) return;
  savingEntryIds.value.add(entryId);
  try {
    await markWordMastered(entryId);
    await loadEntries();
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "标记失败");
  } finally {
    savingEntryIds.value.delete(entryId);
  }
}

async function handleDelete(entryId: number, word: string) {
  const confirmed = window.confirm(`确定删除单词“${word}”吗？`);
  if (!confirmed) {
    return;
  }

  try {
    await deleteWordBookEntry(entryId);
    items.value = items.value.filter((item) => item.entry_id !== entryId);
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "删除失败");
  }
}

onMounted(loadEntries);
</script>
