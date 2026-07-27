<template>
  <div class="login-page">
    <div class="login-card">
      <h1>ReadingCoach 文章录入</h1>
      <p class="muted">请使用孩子的学习账号登录</p>

      <form class="form" @submit.prevent="handleLogin">
        <label class="field">
          <span>手机号</span>
          <input
            v-model="phone"
            type="tel"
            inputmode="numeric"
            maxlength="11"
            placeholder="11 位手机号"
            autocomplete="tel"
          />
        </label>

        <label class="field">
          <span>验证码</span>
          <div class="field-row">
            <input
              v-model="code"
              type="text"
              inputmode="numeric"
              maxlength="6"
              placeholder="6 位验证码"
              autocomplete="one-time-code"
            />
            <button
              class="button button--secondary"
              type="button"
              :disabled="sendingCode || countdown > 0"
              @click="handleSendCode"
            >
              {{ countdown > 0 ? `${countdown}s` : "获取验证码" }}
            </button>
          </div>
        </label>

        <p v-if="debugCode" class="debug-code">开发验证码：{{ debugCode }}</p>
        <p v-if="errorMessage" class="error-text">{{ errorMessage }}</p>

        <button class="button button--primary" type="submit" :disabled="loading">
          {{ loading ? "登录中..." : "登录" }}
        </button>
      </form>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onUnmounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { login, sendCode } from "../api/auth";
import { ApiError } from "../api/client";

const router = useRouter();
const route = useRoute();

const phone = ref("");
const code = ref("");
const debugCode = ref("");
const errorMessage = ref("");
const loading = ref(false);
const sendingCode = ref(false);
const countdown = ref(0);

let timer: number | undefined;

onUnmounted(() => {
  if (timer) {
    window.clearInterval(timer);
  }
});

function startCountdown(seconds: number) {
  countdown.value = seconds;
  timer = window.setInterval(() => {
    countdown.value -= 1;
    if (countdown.value <= 0 && timer) {
      window.clearInterval(timer);
      timer = undefined;
    }
  }, 1000);
}

async function handleSendCode() {
  errorMessage.value = "";
  debugCode.value = "";

  if (!phone.value.trim()) {
    errorMessage.value = "请输入手机号";
    return;
  }

  sendingCode.value = true;
  try {
    const data = await sendCode(phone.value.trim());
    if (data.debugCode) {
      debugCode.value = data.debugCode;
    }
    startCountdown(Math.max(data.expiresIn, 60));
  } catch (error) {
    errorMessage.value =
      error instanceof ApiError ? error.message : "发送验证码失败";
  } finally {
    sendingCode.value = false;
  }
}

async function handleLogin() {
  errorMessage.value = "";
  loading.value = true;

  try {
    await login(phone.value.trim(), code.value.trim());
    const redirect = typeof route.query.redirect === "string"
      ? route.query.redirect
      : "/articles/new";
    await router.replace(redirect);
  } catch (error) {
    errorMessage.value =
      error instanceof ApiError ? error.message : "登录失败";
  } finally {
    loading.value = false;
  }
}
</script>
