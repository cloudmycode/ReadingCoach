<template>
  <AppLayout>
    <section class="panel">
      <div class="panel__header">
        <div>
          <h2>录入文章</h2>
          <p class="muted">粘贴英文正文，系统将自动拆句并翻译入库</p>
        </div>
      </div>

      <form class="form" @submit.prevent="handleSubmit">
        <label class="field">
          <span>英文正文</span>
          <textarea
            v-model="text"
            rows="16"
            placeholder="在此粘贴英文文章正文..."
            :disabled="submitting"
          />
        </label>

        <p v-if="errorMessage" class="error-text">{{ errorMessage }}</p>
        <p v-if="successMessage" class="success-text">{{ successMessage }}</p>

        <div class="actions">
          <button class="button button--primary" type="submit" :disabled="submitting">
            {{ submitting ? "处理中，请稍候..." : "提交并生成文章" }}
          </button>
          <RouterLink
            v-if="createdArticleId"
            class="button button--secondary"
            :to="`/articles/${createdArticleId}`"
          >
            查看详情
          </RouterLink>
          <RouterLink class="button button--ghost" to="/articles">
            文章列表
          </RouterLink>
        </div>
      </form>
    </section>
  </AppLayout>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { RouterLink } from "vue-router";
import AppLayout from "../components/AppLayout.vue";
import { processArticleText } from "../api/articles";
import { ApiError } from "../api/client";

const text = ref("");
const submitting = ref(false);
const errorMessage = ref("");
const successMessage = ref("");
const createdArticleId = ref("");

async function handleSubmit() {
  errorMessage.value = "";
  successMessage.value = "";
  createdArticleId.value = "";

  const payload = text.value.trim();
  if (!payload) {
    errorMessage.value = "正文不能为空";
    return;
  }

  submitting.value = true;
  try {
    const data = await processArticleText(payload);
    createdArticleId.value = data.resource_id;
    successMessage.value = "文章已生成，可在 App 或网页列表中查看";
    text.value = "";
  } catch (error) {
    errorMessage.value =
      error instanceof ApiError ? error.message : "提交失败";
  } finally {
    submitting.value = false;
  }
}
</script>
