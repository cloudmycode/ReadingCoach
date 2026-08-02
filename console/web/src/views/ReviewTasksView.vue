<template>
  <AppLayout>
    <section class="panel">
      <div class="panel__header">
        <div>
          <h2>复习任务</h2>
          <p class="muted">
            今日待复习 {{ summary.due_count }} 个，已完成 {{ summary.completed_count }} 个
          </p>
        </div>
        <div class="actions">
          <button class="button button--secondary" type="button" @click="loadAll">
            刷新
          </button>
          <RouterLink class="button button--ghost" to="/stats">
            学习统计
          </RouterLink>
          <RouterLink class="button button--ghost" to="/word-book">
            查看生词本
          </RouterLink>
        </div>
      </div>

      <div class="stats-grid">
        <div class="stat-card">
          <span class="stat-card__label">今日待复习</span>
          <strong>{{ summary.due_count }}</strong>
        </div>
        <div class="stat-card">
          <span class="stat-card__label">今日已完成</span>
          <strong>{{ summary.completed_count }}</strong>
        </div>
        <div class="stat-card">
          <span class="stat-card__label">每日上限</span>
          <strong>{{ summary.daily_limit }}</strong>
        </div>
        <div class="stat-card">
          <span class="stat-card__label">连续学习</span>
          <strong>{{ summary.streak_days }} 天</strong>
        </div>
      </div>

      <div class="tab-bar">
        <button
          class="tab-bar__button"
          :class="{ 'tab-bar__button--active': activeTab === 'pending' }"
          type="button"
          @click="activeTab = 'pending'"
        >
          待复习
        </button>
        <button
          class="tab-bar__button"
          :class="{ 'tab-bar__button--active': activeTab === 'completed' }"
          type="button"
          @click="activeTab = 'completed'"
        >
          已完成
        </button>
      </div>

      <p v-if="loading" class="muted">加载中...</p>
      <p v-else-if="errorMessage" class="error-text">{{ errorMessage }}</p>

      <template v-else-if="activeTab === 'pending'">
        <div v-if="pendingItems.length === 0" class="empty-state">当前没有待复习任务</div>
        <div v-else class="record-list">
          <article v-for="item in pendingItems" :key="item.entry_id" class="record-card">
            <div class="record-card__main">
              <div class="record-card__title-row">
                <h3>{{ item.word }}</h3>
                <span class="record-badge">阶段 {{ item.review_step }}</span>
              </div>
              <p class="record-card__meta">
                {{ item.part_of_speech || "词性未标注" }} ·
                {{ item.article_title || "来自阅读文章" }}
              </p>
              <p class="record-card__desc">{{ item.meaning || item.tip || "暂无释义" }}</p>
              <p class="record-card__quote">{{ item.sentence_original }}</p>
              <p class="record-card__submeta">下次复习：{{ item.next_review_at || "今天" }}</p>
            </div>
            <div class="record-card__actions">
              <RouterLink class="button button--ghost" :to="`/articles/${item.article_id}`">
                查看文章
              </RouterLink>
              <button
                class="button button--danger"
                type="button"
                @click="handleDelete(item.entry_id, item.word)"
              >
                删除任务
              </button>
            </div>
          </article>
        </div>
      </template>

      <template v-else>
        <div v-if="completedDayGroups.length === 0" class="empty-state">
          还没有已完成任务
        </div>
        <div v-else class="day-group-list">
          <section v-for="group in completedDayGroups" :key="group.key" class="day-group">
            <button class="day-group__header" type="button" @click="toggleDay(group.key)">
              <div>
                <strong>{{ group.title }}</strong>
                <span class="muted">{{ group.items.length }} 个单词</span>
              </div>
              <span
                class="day-group__chevron"
                :class="{ 'day-group__chevron--open': expandedDays.has(group.key) }"
              >
                ›
              </span>
            </button>
            <div v-if="expandedDays.has(group.key)" class="record-list day-group__items">
              <article
                v-for="item in group.items"
                :key="item.log_id || `${item.entry_id}-${item.last_reviewed_at}`"
                class="record-card"
              >
                <div class="record-card__main">
                  <div class="record-card__title-row">
                    <h3>{{ item.word }}</h3>
                    <span
                      v-if="resultLabel(item.result)"
                      class="record-badge"
                      :class="resultClass(item.result)"
                    >
                      {{ resultLabel(item.result) }}
                    </span>
                  </div>
                  <p class="record-card__meta">
                    {{ item.part_of_speech || "词性未标注" }} ·
                    {{ item.article_title || "来自阅读文章" }}
                  </p>
                  <p class="record-card__desc">{{ item.meaning || item.tip || "暂无释义" }}</p>
                  <p class="record-card__quote">{{ item.sentence_original }}</p>
                  <p class="record-card__submeta">
                    完成时间：{{ formatDateTime(item.last_reviewed_at) }}
                  </p>
                </div>
                <div class="record-card__actions">
                  <RouterLink class="button button--ghost" :to="`/articles/${item.article_id}`">
                    查看文章
                  </RouterLink>
                  <button
                    class="button button--danger"
                    type="button"
                    @click="handleDelete(item.entry_id, item.word)"
                  >
                    删除任务
                  </button>
                </div>
              </article>
            </div>
          </section>
        </div>
      </template>
    </section>
  </AppLayout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { RouterLink } from "vue-router";
import AppLayout from "../components/AppLayout.vue";
import { ApiError, formatDateTime } from "../api/client";
import { getReviewSummary, listReviewTasks } from "../api/review";
import { deleteWordBookEntry } from "../api/word-book";
import type { WordReviewSummary, WordReviewTaskItem } from "../types/api";

interface CompletedDayGroup {
  key: string;
  title: string;
  items: WordReviewTaskItem[];
}

const activeTab = ref<"pending" | "completed">("pending");
const loading = ref(false);
const errorMessage = ref("");
const summary = ref<WordReviewSummary>({
  due_count: 0,
  completed_count: 0,
  daily_limit: 20,
  streak_days: 0,
});
const pendingItems = ref<WordReviewTaskItem[]>([]);
const completedItems = ref<WordReviewTaskItem[]>([]);
const expandedDays = ref<Set<string>>(new Set());

const completedDayGroups = computed(() => groupCompletedByDay(completedItems.value));

function dayKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function parseReviewedAt(value?: string): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function dayTitle(key: string, date: Date): string {
  const today = new Date();
  const yesterday = new Date();
  yesterday.setDate(today.getDate() - 1);
  if (key === dayKey(today)) return "今天";
  if (key === dayKey(yesterday)) return "昨天";
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

function groupCompletedByDay(items: WordReviewTaskItem[]): CompletedDayGroup[] {
  const map = new Map<string, CompletedDayGroup>();
  for (const item of items) {
    const reviewedAt = parseReviewedAt(item.last_reviewed_at) ?? new Date(0);
    const key = dayKey(reviewedAt);
    const existing = map.get(key);
    if (existing) {
      existing.items.push(item);
    } else {
      map.set(key, {
        key,
        title: dayTitle(key, reviewedAt),
        items: [item],
      });
    }
  }
  return Array.from(map.values()).sort((a, b) => (a.key < b.key ? 1 : -1));
}

function expandTodayIfNeeded(items: WordReviewTaskItem[]) {
  const today = dayKey(new Date());
  if (
    items.some((item) => {
      const reviewedAt = parseReviewedAt(item.last_reviewed_at);
      return reviewedAt ? dayKey(reviewedAt) === today : false;
    })
  ) {
    const next = new Set(expandedDays.value);
    next.add(today);
    expandedDays.value = next;
  }
}

function toggleDay(key: string) {
  const next = new Set(expandedDays.value);
  if (next.has(key)) {
    next.delete(key);
  } else {
    next.add(key);
  }
  expandedDays.value = next;
}

function resultLabel(result?: string): string {
  switch ((result || "").toLowerCase()) {
    case "mastered":
      return "认识了";
    case "again":
      return "还不熟";
    default:
      return "";
  }
}

function resultClass(result?: string): string {
  switch ((result || "").toLowerCase()) {
    case "mastered":
      return "record-badge--mastered";
    case "again":
      return "record-badge--again";
    default:
      return "";
  }
}

async function loadAll() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const [summaryData, pendingData, completedData] = await Promise.all([
      getReviewSummary(),
      listReviewTasks("pending"),
      listReviewTasks("completed"),
    ]);
    summary.value = summaryData;
    pendingItems.value = pendingData.items;
    completedItems.value = completedData.items;
    expandTodayIfNeeded(completedData.items);
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

async function handleDelete(entryId: number, word: string) {
  const confirmed = window.confirm(`确定删除任务“${word}”吗？这会同时从生词本移除。`);
  if (!confirmed) {
    return;
  }

  try {
    await deleteWordBookEntry(entryId);
    pendingItems.value = pendingItems.value.filter((item) => item.entry_id !== entryId);
    completedItems.value = completedItems.value.filter((item) => item.entry_id !== entryId);
    summary.value = {
      ...summary.value,
      due_count: Math.max(
        0,
        summary.value.due_count - (activeTab.value === "pending" ? 1 : 0),
      ),
      completed_count: Math.max(
        0,
        summary.value.completed_count - (activeTab.value === "completed" ? 1 : 0),
      ),
    };
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "删除失败");
  }
}

onMounted(loadAll);
</script>
