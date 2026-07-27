<template>
  <AppLayout>
    <section class="panel">
      <div class="panel__header">
        <div>
          <h2>文章列表</h2>
          <p class="muted">共 {{ items.length }} 篇</p>
        </div>
        <div class="actions">
          <button class="button button--secondary" type="button" @click="loadArticles">
            刷新
          </button>
          <RouterLink class="button button--primary" to="/articles/new">
            录入文章
          </RouterLink>
        </div>
      </div>

      <p v-if="loading" class="muted">加载中...</p>
      <p v-else-if="errorMessage" class="error-text">{{ errorMessage }}</p>

      <div v-else-if="items.length === 0" class="empty-state">
        还没有文章，先去录入一篇吧。
      </div>

      <div v-else class="article-list">
        <article v-for="item in items" :key="item.id" class="article-card">
          <div class="article-card__main">
            <RouterLink :to="`/articles/${item.id}`" class="article-card__title">
              {{ item.title || "未命名文章" }}
            </RouterLink>
            <p class="article-card__meta">
              {{ item.sentence_count }} 句 · 阅读 {{ item.read_count }} 次 ·
              创建于 {{ formatDateTime(item.created_at) }}
            </p>
          </div>
          <div class="article-card__actions">
            <RouterLink class="button button--ghost" :to="`/articles/${item.id}`">
              查看
            </RouterLink>
            <button
              class="button button--danger"
              type="button"
              @click="handleDelete(item.id, item.title)"
            >
              删除
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
import { deleteArticle, listArticles } from "../api/articles";
import { ApiError, formatDateTime } from "../api/client";
import type { ArticleListItem } from "../types/api";

const items = ref<ArticleListItem[]>([]);
const loading = ref(false);
const errorMessage = ref("");

async function loadArticles() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const data = await listArticles();
    items.value = data.items;
  } catch (error) {
    errorMessage.value =
      error instanceof ApiError ? error.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

async function handleDelete(id: string, title: string) {
  const confirmed = window.confirm(`确定删除《${title || "未命名文章"}》吗？`);
  if (!confirmed) {
    return;
  }

  try {
    await deleteArticle(id);
    items.value = items.value.filter((item) => item.id !== id);
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "删除失败");
  }
}

onMounted(loadArticles);
</script>
