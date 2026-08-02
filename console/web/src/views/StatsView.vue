<template>
  <AppLayout>
    <section class="panel">
      <div class="panel__header">
        <div>
          <h2>学习统计</h2>
          <p class="muted">近 14 天阅读与单词复习进展</p>
        </div>
        <div class="actions">
          <button class="button button--secondary" type="button" @click="loadAll">
            刷新
          </button>
          <RouterLink class="button button--ghost" to="/review-tasks">
            复习任务
          </RouterLink>
        </div>
      </div>

      <p v-if="loading" class="muted">加载中...</p>
      <p v-else-if="errorMessage" class="error-text">{{ errorMessage }}</p>

      <template v-else>
        <div class="stats-grid">
          <div class="stat-card">
            <span class="stat-card__label">今日阅读</span>
            <strong>{{ formatDurationMinutes(stats.today_read_seconds) }}</strong>
          </div>
          <div class="stat-card">
            <span class="stat-card__label">今日复习</span>
            <strong>{{ formatDurationMinutes(stats.today_review_seconds) }}</strong>
          </div>
          <div class="stat-card">
            <span class="stat-card__label">阅读速度</span>
            <strong>
              {{ stats.average_reading_speed_wpm ? `${stats.average_reading_speed_wpm}` : "—" }}
            </strong>
            <span class="stat-card__label">词/分钟</span>
          </div>
          <div class="stat-card">
            <span class="stat-card__label">连续坚持</span>
            <strong>{{ stats.current_streak_days }} 天</strong>
          </div>
        </div>

        <div class="stats-summary">
          <div class="stats-summary__item">
            <span class="muted">累计阅读时长</span>
            <strong>{{ formatDurationMinutes(stats.total_read_seconds) }}</strong>
          </div>
          <div class="stats-summary__item">
            <span class="muted">今日复习词数</span>
            <strong>{{ stats.today_review_count }} 词</strong>
          </div>
          <div class="stats-summary__item">
            <span class="muted">累计文章</span>
            <strong>{{ stats.total_articles }} 篇</strong>
          </div>
        </div>

        <div class="chart-grid">
          <section class="chart-card">
            <div class="chart-card__header">
              <div>
                <h3>文章趋势</h3>
                <p class="muted">近 14 天每日新读篇数</p>
              </div>
              <span class="chart-card__total">合计 {{ totalRecentArticles }} 篇</span>
            </div>
            <div v-if="articlePoints.length === 0" class="chart-card__empty">暂无数据</div>
            <div v-else class="bar-chart" role="img" aria-label="文章趋势图">
              <div
                v-for="point in articlePoints"
                :key="`article-${point.date}`"
                class="bar-chart__col"
              >
                <span class="bar-chart__value">{{ point.count || "" }}</span>
                <div class="bar-chart__track">
                  <div
                    class="bar-chart__bar bar-chart__bar--article-count"
                    :style="{ height: `${barHeight(point.count, maxArticles)}%` }"
                  />
                </div>
                <span class="bar-chart__label">{{ shortDate(point.date) }}</span>
              </div>
            </div>
          </section>

          <section class="chart-card">
            <div class="chart-card__header">
              <div>
                <h3>阅读时长</h3>
                <p class="muted">近 14 天每日阅读分钟数</p>
              </div>
              <span class="chart-card__total">合计 {{ totalRecentReadMinutes }} 分</span>
            </div>
            <div v-if="readDurationPoints.length === 0" class="chart-card__empty">暂无数据</div>
            <div v-else class="bar-chart" role="img" aria-label="阅读时长趋势图">
              <div
                v-for="point in readDurationPoints"
                :key="`read-${point.date}`"
                class="bar-chart__col"
              >
                <span class="bar-chart__value">{{ point.count || "" }}</span>
                <div class="bar-chart__track">
                  <div
                    class="bar-chart__bar bar-chart__bar--article"
                    :style="{ height: `${barHeight(point.count, maxReadMinutes)}%` }"
                  />
                </div>
                <span class="bar-chart__label">{{ shortDate(point.date) }}</span>
              </div>
            </div>
          </section>

          <section class="chart-card">
            <div class="chart-card__header">
              <div>
                <h3>复习时长</h3>
                <p class="muted">近 14 天每日复习分钟数</p>
              </div>
              <span class="chart-card__total">合计 {{ totalRecentReviewMinutes }} 分</span>
            </div>
            <div v-if="reviewDurationPoints.length === 0" class="chart-card__empty">暂无数据</div>
            <div v-else class="bar-chart" role="img" aria-label="复习时长趋势图">
              <div
                v-for="point in reviewDurationPoints"
                :key="`review-min-${point.date}`"
                class="bar-chart__col"
              >
                <span class="bar-chart__value">{{ point.count || "" }}</span>
                <div class="bar-chart__track">
                  <div
                    class="bar-chart__bar bar-chart__bar--review"
                    :style="{ height: `${barHeight(point.count, maxReviewMinutes)}%` }"
                  />
                </div>
                <span class="bar-chart__label">{{ shortDate(point.date) }}</span>
              </div>
            </div>
          </section>

          <section class="chart-card">
            <div class="chart-card__header">
              <div>
                <h3>单词复习</h3>
                <p class="muted">近 14 天每日复习单词数量</p>
              </div>
              <span class="chart-card__total">合计 {{ totalRecentReviews }} 词</span>
            </div>
            <div v-if="reviewPoints.length === 0" class="chart-card__empty">暂无数据</div>
            <div v-else class="bar-chart" role="img" aria-label="单词复习趋势图">
              <button
                v-for="point in reviewPoints"
                :key="`review-${point.date}`"
                class="bar-chart__col bar-chart__col--button"
                :class="{ 'bar-chart__col--active': selectedDay === point.date }"
                type="button"
                @click="selectDay(point.date)"
              >
                <span class="bar-chart__value">{{ point.count || "" }}</span>
                <div class="bar-chart__track">
                  <div
                    class="bar-chart__bar bar-chart__bar--again"
                    :style="{ height: `${barHeight(point.count, maxReviews)}%` }"
                  />
                </div>
                <span class="bar-chart__label">{{ shortDate(point.date) }}</span>
              </button>
            </div>
          </section>
        </div>

        <section class="detail-panel">
          <div class="detail-panel__header">
            <div>
              <h3>每日复习详情</h3>
              <p class="muted">点击日期查看当天复习的单词，以及「认识了 / 还不熟」</p>
            </div>
          </div>

          <div v-if="reviewDayGroups.length === 0" class="empty-state">
            近 14 天还没有复习记录
          </div>

          <div v-else class="day-group-list">
            <section
              v-for="group in reviewDayGroups"
              :key="group.key"
              class="day-group"
            >
              <button
                class="day-group__header"
                :class="{ 'day-group__header--active': selectedDay === group.key }"
                type="button"
                @click="toggleDay(group.key)"
              >
                <div>
                  <strong>{{ group.title }}</strong>
                  <span class="muted">
                    {{ group.count }} 个单词
                    <template v-if="dayDurationText(group.key)">
                      · {{ dayDurationText(group.key) }}
                    </template>
                    <template v-if="group.masteredCount || group.againCount">
                      · 认识了 {{ group.masteredCount }} · 还不熟 {{ group.againCount }}
                    </template>
                  </span>
                </div>
                <span
                  class="day-group__chevron"
                  :class="{ 'day-group__chevron--open': selectedDay === group.key }"
                >
                  ›
                </span>
              </button>

              <div v-if="selectedDay === group.key" class="record-list day-group__items">
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
                    <p class="record-card__desc">
                      {{ item.meaning || item.tip || "暂无释义" }}
                    </p>
                    <p class="record-card__submeta">
                      完成时间：{{ formatDateTime(item.last_reviewed_at) }}
                    </p>
                  </div>
                  <div class="record-card__actions">
                    <RouterLink
                      class="button button--ghost"
                      :to="`/articles/${item.article_id}`"
                    >
                      查看文章
                    </RouterLink>
                  </div>
                </article>
              </div>
            </section>
          </div>
        </section>
      </template>
    </section>
  </AppLayout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { RouterLink } from "vue-router";
import AppLayout from "../components/AppLayout.vue";
import { ApiError, formatDateTime } from "../api/client";
import { listReviewTasks } from "../api/review";
import { formatDurationMinutes, getStudyStatsOverview } from "../api/stats";
import type {
  DailyStudyStat,
  StudyStatsOverview,
  WordReviewTaskItem,
} from "../types/api";

interface ChartPoint {
  date: string;
  count: number;
}

interface ReviewDayGroup {
  key: string;
  title: string;
  count: number;
  masteredCount: number;
  againCount: number;
  items: WordReviewTaskItem[];
}

const loading = ref(false);
const errorMessage = ref("");
const selectedDay = ref("");
const stats = ref<StudyStatsOverview>({
  total_articles: 0,
  today_new_articles: 0,
  today_review_count: 0,
  today_read_seconds: 0,
  today_review_seconds: 0,
  current_streak_days: 0,
  total_read_count: 0,
  total_sentence_count: 0,
  total_read_seconds: 0,
  recent_days: [],
});
const completedItems = ref<WordReviewTaskItem[]>([]);

const articlePoints = computed<ChartPoint[]>(() =>
  (stats.value.recent_days || []).map((day) => ({
    date: day.date,
    count: day.new_articles,
  })),
);

const readDurationPoints = computed<ChartPoint[]>(() =>
  (stats.value.recent_days || []).map((day) => ({
    date: day.date,
    count: Math.ceil((day.read_seconds || 0) / 60),
  })),
);

const reviewDurationPoints = computed<ChartPoint[]>(() =>
  (stats.value.recent_days || []).map((day) => ({
    date: day.date,
    count: Math.ceil((day.review_seconds || 0) / 60),
  })),
);

const reviewPoints = computed<ChartPoint[]>(() =>
  (stats.value.recent_days || []).map((day) => ({
    date: day.date,
    count: day.review_count,
  })),
);

const maxArticles = computed(() =>
  Math.max(...articlePoints.value.map((item) => item.count), 1),
);

const maxReadMinutes = computed(() =>
  Math.max(...readDurationPoints.value.map((item) => item.count), 1),
);

const maxReviewMinutes = computed(() =>
  Math.max(...reviewDurationPoints.value.map((item) => item.count), 1),
);

const maxReviews = computed(() =>
  Math.max(...reviewPoints.value.map((item) => item.count), 1),
);

const totalRecentArticles = computed(() =>
  articlePoints.value.reduce((sum, item) => sum + item.count, 0),
);

const totalRecentReadMinutes = computed(() =>
  readDurationPoints.value.reduce((sum, item) => sum + item.count, 0),
);

const totalRecentReviewMinutes = computed(() =>
  reviewDurationPoints.value.reduce((sum, item) => sum + item.count, 0),
);

const totalRecentReviews = computed(() =>
  reviewPoints.value.reduce((sum, item) => sum + item.count, 0),
);

const reviewDayGroups = computed(() => {
  const recentDates = new Set(
    (stats.value.recent_days || []).map((day: DailyStudyStat) => day.date),
  );
  const map = new Map<string, WordReviewTaskItem[]>();

  for (const item of completedItems.value) {
    const key = dayKeyFromValue(item.last_reviewed_at);
    if (!key || (recentDates.size > 0 && !recentDates.has(key))) {
      continue;
    }
    const list = map.get(key) || [];
    list.push(item);
    map.set(key, list);
  }

  // 即使某天统计有数量但详情日志缺失，也用统计日期补齐空组，方便对照。
  for (const day of stats.value.recent_days || []) {
    if (day.review_count > 0 && !map.has(day.date)) {
      map.set(day.date, []);
    }
  }

  return Array.from(map.entries())
    .map(([key, items]) => {
      const sortedItems = [...items].sort((a, b) =>
        (b.last_reviewed_at || "").localeCompare(a.last_reviewed_at || ""),
      );
      const masteredCount = sortedItems.filter(
        (item) => (item.result || "").toLowerCase() === "mastered",
      ).length;
      const againCount = sortedItems.filter(
        (item) => (item.result || "").toLowerCase() === "again",
      ).length;
      const countFromStats =
        stats.value.recent_days.find((day) => day.date === key)?.review_count || 0;
      return {
        key,
        title: dayTitle(key),
        count: sortedItems.length || countFromStats,
        masteredCount,
        againCount,
        items: sortedItems,
      } satisfies ReviewDayGroup;
    })
    .filter((group) => group.count > 0)
    .sort((a, b) => (a.key < b.key ? 1 : -1));
});

function shortDate(value: string): string {
  const parts = value.split("-");
  if (parts.length !== 3) return value;
  return `${Number(parts[1])}/${Number(parts[2])}`;
}

function formatLocalDayKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function dayKeyFromValue(value?: string): string {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value.slice(0, 10);
  }
  return formatLocalDayKey(date);
}

function dayTitle(key: string): string {
  const today = formatLocalDayKey(new Date());
  const yesterdayDate = new Date();
  yesterdayDate.setDate(yesterdayDate.getDate() - 1);
  const yesterday = formatLocalDayKey(yesterdayDate);
  if (key === today) return "今天";
  if (key === yesterday) return "昨天";
  const parts = key.split("-");
  if (parts.length !== 3) return key;
  return `${Number(parts[1])}月${Number(parts[2])}日`;
}

function barHeight(count: number, max: number): number {
  if (count <= 0) return 0;
  return Math.max(8, Math.round((count / max) * 100));
}

function dayDurationText(dateKey: string): string {
  const day = (stats.value.recent_days || []).find((item) => item.date === dateKey);
  if (!day) return "";
  const parts: string[] = [];
  if (day.read_seconds > 0) {
    parts.push(`阅读 ${formatDurationMinutes(day.read_seconds)}`);
  }
  if (day.review_seconds > 0) {
    parts.push(`复习 ${formatDurationMinutes(day.review_seconds)}`);
  }
  return parts.join(" · ");
}

function selectDay(date: string) {
  selectedDay.value = selectedDay.value === date ? "" : date;
}

function toggleDay(date: string) {
  selectDay(date);
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

function ensureSelectedDay() {
  if (selectedDay.value && reviewDayGroups.value.some((g) => g.key === selectedDay.value)) {
    return;
  }
  const today = formatLocalDayKey(new Date());
  if (reviewDayGroups.value.some((g) => g.key === today)) {
    selectedDay.value = today;
    return;
  }
  selectedDay.value = reviewDayGroups.value[0]?.key || "";
}

async function loadAll() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const [statsData, completedData] = await Promise.all([
      getStudyStatsOverview(14),
      listReviewTasks("completed"),
    ]);
    stats.value = statsData;
    completedItems.value = completedData.items;
    ensureSelectedDay();
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

onMounted(loadAll);
</script>
