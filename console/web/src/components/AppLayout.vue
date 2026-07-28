<template>
  <div class="layout">
    <header class="layout__header">
      <div class="layout__brand">
        <RouterLink to="/articles" class="layout__title">ReadingCoach</RouterLink>
        <span class="layout__subtitle">学习管理</span>
      </div>

      <nav class="layout__nav">
        <RouterLink to="/articles" class="nav-link">文章列表</RouterLink>
        <RouterLink to="/review-tasks" class="nav-link">复习任务</RouterLink>
        <RouterLink to="/word-book" class="nav-link">生词本</RouterLink>
      </nav>

      <div class="layout__user">
        <span v-if="nickname" class="layout__nickname">{{ nickname }}</span>
        <button class="button button--ghost" type="button" @click="handleLogout">
          退出
        </button>
      </div>
    </header>

    <main class="layout__main">
      <slot />
    </main>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { fetchCurrentUser, logout } from "../api/auth";
import { ApiError } from "../api/client";

const router = useRouter();
const nickname = ref("");

onMounted(async () => {
  try {
    const user = await fetchCurrentUser();
    nickname.value = user.nickname;
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      await router.push({ name: "login" });
    }
  }
});

async function handleLogout() {
  await logout();
  await router.push({ name: "login" });
}
</script>
