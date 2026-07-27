import { createRouter, createWebHistory } from "vue-router";
import { getToken } from "../api/client";
import LoginView from "../views/LoginView.vue";
import CreateArticleView from "../views/CreateArticleView.vue";
import ArticleListView from "../views/ArticleListView.vue";
import ArticleDetailView from "../views/ArticleDetailView.vue";

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: "/login",
      name: "login",
      component: LoginView,
      meta: { guest: true },
    },
    {
      path: "/",
      redirect: "/articles/new",
    },
    {
      path: "/articles/new",
      name: "create-article",
      component: CreateArticleView,
      meta: { requiresAuth: true },
    },
    {
      path: "/articles",
      name: "article-list",
      component: ArticleListView,
      meta: { requiresAuth: true },
    },
    {
      path: "/articles/:id",
      name: "article-detail",
      component: ArticleDetailView,
      meta: { requiresAuth: true },
    },
  ],
});

router.beforeEach((to) => {
  const authed = Boolean(getToken());

  if (to.meta.requiresAuth && !authed) {
    return { name: "login", query: { redirect: to.fullPath } };
  }

  if (to.meta.guest && authed) {
    return { name: "create-article" };
  }

  return true;
});

export default router;
