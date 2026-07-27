<template>
  <AppLayout>
    <section class="panel">
      <div class="panel__header">
        <div>
          <RouterLink to="/articles" class="back-link">← 返回列表</RouterLink>
          <h2>{{ article?.title || "文章详情" }}</h2>
          <p v-if="article" class="muted">
            {{ article.sentence_count }} 句
          </p>
        </div>
        <div v-if="article" class="actions">
          <button class="button button--secondary" type="button" @click="startEditTitle">
            改标题
          </button>
          <button class="button button--danger" type="button" @click="handleDelete">
            删除文章
          </button>
        </div>
      </div>

      <div v-if="editingTitle" class="inline-form">
        <input v-model="titleDraft" maxlength="60" />
        <button class="button button--primary" type="button" @click="saveTitle">
          保存
        </button>
        <button class="button button--ghost" type="button" @click="cancelEditTitle">
          取消
        </button>
      </div>

      <p v-if="loading" class="muted">加载中...</p>
      <p v-else-if="errorMessage" class="error-text">{{ errorMessage }}</p>

      <div v-else-if="article" class="sentence-list">
        <article
          v-for="(sentence, index) in article.sentences"
          :key="sentence.sentence_id || index"
          class="sentence-card"
        >
          <div class="sentence-card__header">
            <span class="sentence-card__index">第 {{ index + 1 }} 句</span>
            <button
              v-if="editingSentenceId !== sentence.sentence_id"
              class="button button--ghost"
              type="button"
              @click="startEditSentence(sentence.sentence_id, sentence.original)"
            >
              纠错
            </button>
          </div>

          <template v-if="editingSentenceId === sentence.sentence_id">
            <textarea v-model="sentenceDraft" rows="3" />
            <div class="actions">
              <button
                class="button button--primary"
                type="button"
                :disabled="savingSentence"
                @click="saveSentence(sentence.sentence_id)"
              >
                {{ savingSentence ? "保存中..." : "保存并重译" }}
              </button>
              <button class="button button--ghost" type="button" @click="cancelEditSentence">
                取消
              </button>
            </div>
          </template>

          <template v-else>
            <p class="sentence-card__original">{{ sentence.original }}</p>
            <p class="sentence-card__translation">{{ sentence.translation }}</p>
          </template>
        </article>
      </div>
    </section>
  </AppLayout>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue";
import { RouterLink, useRoute, useRouter } from "vue-router";
import AppLayout from "../components/AppLayout.vue";
import {
  deleteArticle,
  getArticleDetail,
  updateArticleTitle,
  updateSentence,
} from "../api/articles";
import { ApiError } from "../api/client";
import type { ArticleDetail } from "../types/api";

const route = useRoute();
const router = useRouter();

const article = ref<ArticleDetail | null>(null);
const loading = ref(false);
const errorMessage = ref("");
const editingTitle = ref(false);
const titleDraft = ref("");
const editingSentenceId = ref<number | null>(null);
const sentenceDraft = ref("");
const savingSentence = ref(false);

const articleId = () => String(route.params.id);

async function loadDetail() {
  loading.value = true;
  errorMessage.value = "";

  try {
    article.value = await getArticleDetail(articleId());
  } catch (error) {
    errorMessage.value =
      error instanceof ApiError ? error.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function startEditTitle() {
  if (!article.value) {
    return;
  }
  titleDraft.value = article.value.title;
  editingTitle.value = true;
}

function cancelEditTitle() {
  editingTitle.value = false;
  titleDraft.value = "";
}

async function saveTitle() {
  if (!article.value) {
    return;
  }

  const title = titleDraft.value.trim();
  if (!title) {
    window.alert("标题不能为空");
    return;
  }

  try {
    const data = await updateArticleTitle(articleId(), title);
    article.value.title = data.title;
    editingTitle.value = false;
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "更新标题失败");
  }
}

async function handleDelete() {
  const confirmed = window.confirm("确定删除这篇文章吗？");
  if (!confirmed) {
    return;
  }

  try {
    await deleteArticle(articleId());
    await router.push({ name: "article-list" });
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "删除失败");
  }
}

function startEditSentence(sentenceId: number, original: string) {
  editingSentenceId.value = sentenceId;
  sentenceDraft.value = original;
}

function cancelEditSentence() {
  editingSentenceId.value = null;
  sentenceDraft.value = "";
}

async function saveSentence(sentenceId: number) {
  const original = sentenceDraft.value.trim();
  if (!original) {
    window.alert("句子内容不能为空");
    return;
  }

  savingSentence.value = true;
  try {
    const updated = await updateSentence(articleId(), sentenceId, original);
    if (article.value) {
      article.value.sentences = article.value.sentences.map((sentence) =>
        sentence.sentence_id === sentenceId ? updated : sentence,
      );
    }
    cancelEditSentence();
  } catch (error) {
    window.alert(error instanceof ApiError ? error.message : "句子更新失败");
  } finally {
    savingSentence.value = false;
  }
}

onMounted(loadDetail);
</script>
